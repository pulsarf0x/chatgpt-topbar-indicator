#!/usr/bin/env python3
"""Generate the dependency-free Xcode project deterministically."""
import hashlib
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = (ROOT / 'VERSION').read_text().strip()
PROJECT = ROOT / 'QuotaBar.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}

def uid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def obj(key, isa, **fields):
    ident = uid(key)
    objects[ident] = dict(isa=isa, **fields)
    return ident

def ref(path, filetype):
    return obj('ref:' + path, 'PBXFileReference', lastKnownFileType=filetype, path=path, sourceTree='SOURCE_ROOT')

files = {}
for path in sorted((ROOT / 'Sources').rglob('*.swift')):
    rel = str(path.relative_to(ROOT))
    files[rel] = ref(rel, 'sourcecode.swift')
assets = ref('Assets.xcassets', 'folder.assetcatalog')
products = []
targets = []
core = [p for p in files if p.startswith('Sources/QuotaCore/')]
app = [p for p in files if p.startswith('Sources/QuotaBar/')]
shared_widget = ['Sources/QuotaBar/SnapshotStore.swift', 'Sources/QuotaBar/QuotaStyle.swift']
widget = [p for p in files if p.startswith('Sources/QuotaWidgets/')]

for platform in ['macOS', 'iOS']:
    for extension in [True, False]:
        name = ('QuotaWidgets' if extension else 'QuotaBar') + '-' + platform
        product_name = name + ('.appex' if extension else '.app')
        product = obj('product:' + name, 'PBXFileReference', explicitFileType='wrapper.app-extension' if extension else 'wrapper.application', includeInIndex='0', path=product_name, sourceTree='BUILT_PRODUCTS_DIR')
        products.append(product)
        paths = core + (shared_widget + widget if extension else app)
        build_files = [obj(name + ':' + p, 'PBXBuildFile', fileRef=files[p]) for p in paths]
        sources = obj(name + ':sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=build_files, runOnlyForDeploymentPostprocessing='0')
        resources = obj(name + ':resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=[] if extension else [obj(name + ':assets', 'PBXBuildFile', fileRef=assets)], runOnlyForDeploymentPostprocessing='0')
        frameworks = obj(name + ':frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')
        phases = [sources, frameworks, resources]
        dependencies = []
        if not extension:
            widget_name = 'QuotaWidgets-' + platform
            proxy = obj(name + ':proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=uid('target:' + widget_name), remoteInfo=widget_name)
            dependencies.append(obj(name + ':dependency', 'PBXTargetDependency', target=uid('target:' + widget_name), targetProxy=proxy))
            embed = obj(name + ':embedfile', 'PBXBuildFile', fileRef=uid('product:' + widget_name), settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
            phases.append(obj(name + ':embed', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=[embed], name='Embed App Extensions', runOnlyForDeploymentPostprocessing='0'))
        settings = {
            'PRODUCT_NAME': name,
            'PRODUCT_BUNDLE_IDENTIFIER': 'net.plumia.QuotaBar' + ('.widgets' if extension else ''),
            'SWIFT_VERSION': '6.0',
            'GENERATE_INFOPLIST_FILE': 'NO',
            'INFOPLIST_FILE': f'Configuration/{"Widget" if extension else "App"}-{platform}.plist',
            'CODE_SIGN_STYLE': 'Automatic',
            'CODE_SIGN_ENTITLEMENTS': f'Configuration/{"Widget" if extension else "App"}-{platform}.entitlements',
            'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': VERSION,
            'SDKROOT': 'macosx' if platform == 'macOS' else 'iphoneos',
            'SUPPORTED_PLATFORMS': 'macosx' if platform == 'macOS' else 'iphoneos iphonesimulator',
            'MACOSX_DEPLOYMENT_TARGET': '14.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
            'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/Frameworks'],
            'ENABLE_HARDENED_RUNTIME': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'complete',
        }
        if not extension:
            settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
        if extension:
            settings.update(APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES')
        if platform == 'iOS':
            settings['TARGETED_DEVICE_FAMILY'] = '1,2'
        configs = []
        for configuration in ['Debug', 'Release']:
            flags = dict(settings)
            flags['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if configuration == 'Debug' else '-O'
            configs.append(obj(name + ':' + configuration, 'XCBuildConfiguration', buildSettings=flags, name=configuration))
        configlist = obj(name + ':configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
        target = obj('target:' + name, 'PBXNativeTarget', buildConfigurationList=configlist, buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product, productType='com.apple.product-type.app-extension' if extension else 'com.apple.product-type.application')
        targets.append(target)

product_group = obj('products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
main_group = obj('main', 'PBXGroup', children=list(files.values()) + [assets, product_group], sourceTree='<group>')
project_configs = [obj('project:' + name, 'XCBuildConfiguration', buildSettings={'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '6.0', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'}, name=name) for name in ['Debug', 'Release']]
project_configlist = obj('project:configs', 'XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')
obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '2600', 'BuildIndependentTargetsInParallel': 'YES'}, buildConfigurationList=project_configlist, compatibilityVersion='Xcode 14.0', developmentRegion='fr', hasScannedForEncodings='0', knownRegions=['fr', 'en', 'Base'], mainGroup=main_group, productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)

def quote(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

def serialize(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + '\n'.join('\t' * (indent + 1) + quote(k) + ' = ' + serialize(v, indent + 1) + ';' for k, v in value.items()) + '\n' + '\t' * indent + '}'
    if isinstance(value, list):
        return '(' + ', '.join(serialize(v, indent + 1) for v in value) + ')'
    return quote(value)

(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize({'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': uid('project')}) + '\n')
schemes = PROJECT / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
for platform in ['macOS', 'iOS']:
    name = 'QuotaBar-' + platform
    (schemes / (name + '.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:' + name)}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:QuotaBar.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target:' + name)}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:QuotaBar.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

for platform in ['macOS', 'iOS']:
    for extension in [True, False]:
        prefix = 'Widget' if extension else 'App'
        info = dict(CFBundleDevelopmentRegion='fr', CFBundleDisplayName='QuotaBar', CFBundleExecutable='$(EXECUTABLE_NAME)', CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleInfoDictionaryVersion='6.0', CFBundleName='$(PRODUCT_NAME)', CFBundlePackageType='XPC!' if extension else 'APPL', CFBundleShortVersionString='$(MARKETING_VERSION)', CFBundleVersion='$(CURRENT_PROJECT_VERSION)')
        if extension:
            info['NSExtension'] = {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}
        else:
            info['CFBundleURLTypes'] = [{'CFBundleURLName': 'net.plumia.QuotaBar', 'CFBundleURLSchemes': ['quotabar']}]
            if platform == 'macOS':
                info['LSUIElement'] = True
                info['NSPrincipalClass'] = 'NSApplication'
                info['LSMinimumSystemVersion'] = '$(MACOSX_DEPLOYMENT_TARGET)'
            else:
                info['UILaunchScreen'] = {}
                info['UIApplicationSceneManifest'] = {'UIApplicationSupportsMultipleScenes': False}
                info['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
        entitlements = {'com.apple.security.application-groups': ['group.net.plumia.QuotaBar']}
        if platform == 'macOS':
            entitlements['com.apple.security.app-sandbox'] = extension
        if not extension:
            entitlements['com.apple.developer.ubiquity-kvstore-identifier'] = '$(TeamIdentifierPrefix)net.plumia.QuotaBar'
        for suffix, data in [('plist', info), ('entitlements', entitlements)]:
            with (ROOT / f'Configuration/{prefix}-{platform}.{suffix}').open('wb') as out:
                plistlib.dump(data, out)
print('Generated QuotaBar.xcodeproj (macOS + iOS + two widget extensions)')

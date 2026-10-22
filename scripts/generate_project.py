#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only the Python standard library."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ref(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def add(label, isa, **values):
    identifier = ref(label)
    objects[identifier] = dict(isa=isa, **values)
    return identifier


def serialize(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        lines = ["{"]
        for key, child in value.items():
            lines.append(f'{indent}\t{json.dumps(key)} = {serialize(child, level + 1)};')
        return "\n".join(lines) + f"\n{indent}}}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{serialize(child, level + 1)},\n" for child in value) + indent + ")"
    return json.dumps(str(value), ensure_ascii=False)


def configurations(label, base):
    identifiers = []
    for name in ("Debug", "Release"):
        settings = dict(base)
        settings.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O")
        if label == "project":
            settings.update(DEBUG_INFORMATION_FORMAT="dwarf" if name == "Debug" else "dwarf-with-dsym")
            if name == "Debug":
                settings.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG")
        identifiers.append(add(f"{label}-{name}", "XCBuildConfiguration", buildSettings=settings, name=name))
    return add(f"{label}-configs", "XCConfigurationList", buildConfigurations=identifiers,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


groups = []
phases = {}
for folder in ("MomentCamera", "MomentCameraTests"):
    children, sources, resources = [], [], []
    for path in sorted((ROOT / folder).iterdir()):
        if path.suffix not in (".swift", ".plist", ".xcassets", ".xcprivacy"):
            continue
        filetype = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml"}[path.suffix]
        file_ref = add(f"file-{folder}-{path.name}", "PBXFileReference", lastKnownFileType=filetype,
                       path=path.name, sourceTree="<group>")
        children.append(file_ref)
        if path.suffix in (".swift", ".xcassets", ".xcprivacy"):
            build_ref = add(f"build-{folder}-{path.name}", "PBXBuildFile", fileRef=file_ref)
            (sources if path.suffix == ".swift" else resources).append(build_ref)
    groups.append(add(f"group-{folder}", "PBXGroup", children=children, path=folder, sourceTree="<group>"))
    phases[folder] = [
        add(f"{folder}-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0),
        add(f"{folder}-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
        add(f"{folder}-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0),
    ]

app_product = add("app-product", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex=0, path="MomentCamera.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex=0, path="MomentCameraTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=groups + [products], sourceTree="<group>")
project_config = configurations("project", dict(
    SDKROOT="iphoneos", IPHONEOS_DEPLOYMENT_TARGET="17.0", SWIFT_VERSION="5.0",
    CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", GCC_C_LANGUAGE_STANDARD="gnu17",
    SWIFT_STRICT_CONCURRENCY="targeted", ENABLE_USER_SCRIPT_SANDBOXING="YES",
))
common = dict(TARGETED_DEVICE_FAMILY="1", CODE_SIGN_STYLE="Automatic", PRODUCT_NAME="$(TARGET_NAME)",
              SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SUPPORTS_MACCATALYST="NO")
app_config = configurations("app", dict(common,
    PRODUCT_BUNDLE_IDENTIFIER="com.momentcamera.iphone", INFOPLIST_FILE="MomentCamera/Info.plist",
    GENERATE_INFOPLIST_FILE="NO", MARKETING_VERSION="1.0.0", CURRENT_PROJECT_VERSION="1",
    ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"],
))
test_config = configurations("tests", dict(common,
    PRODUCT_BUNDLE_IDENTIFIER="com.momentcamera.iphone.tests", GENERATE_INFOPLIST_FILE="YES",
    BUNDLE_LOADER="$(TEST_HOST)", TEST_HOST="$(BUILT_PRODUCTS_DIR)/MomentCamera.app/MomentCamera",
    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
))
app_target = add("app-target", "PBXNativeTarget", buildConfigurationList=app_config,
                 buildPhases=phases["MomentCamera"], buildRules=[], dependencies=[], name="MomentCamera",
                 productName="MomentCamera", productReference=app_product, productType="com.apple.product-type.application")
proxy = add("test-proxy", "PBXContainerItemProxy", containerPortal=ref("project"), proxyType=1,
            remoteGlobalIDString=app_target, remoteInfo="MomentCamera")
dependency = add("test-dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
test_target = add("test-target", "PBXNativeTarget", buildConfigurationList=test_config,
                  buildPhases=phases["MomentCameraTests"], buildRules=[], dependencies=[dependency],
                  name="MomentCameraTests", productName="MomentCameraTests", productReference=test_product,
                  productType="com.apple.product-type.bundle.unit-test")
project = add("project", "PBXProject", attributes=dict(
    BuildIndependentTargetsInParallel="YES", LastUpgradeCheck="1600",
    TargetAttributes={app_target: dict(CreatedOnToolsVersion="16.0"),
                      test_target: dict(CreatedOnToolsVersion="16.0", TestTargetID=app_target)},
), buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="zh_CN",
   hasScannedForEncodings=0, knownRegions=["zh_CN", "en", "Base"], mainGroup=main_group,
   productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, test_target])

project_dir = ROOT / "MomentCamera.xcodeproj"
project_dir.mkdir(exist_ok=True)
payload = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(payload) + "\n")

scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def buildable(identifier, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:MomentCamera.xcodeproj"/>'


app_reference = buildable(app_target, "MomentCamera.app", "MomentCamera")
test_reference = buildable(test_target, "MomentCameraTests.xctest", "MomentCameraTests")
(scheme_dir / "MomentCamera.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_reference}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">{test_reference}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_reference}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_reference}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated MomentCamera.xcodeproj")

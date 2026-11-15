#!/usr/bin/env python3
"""Generate CourtCall.xcodeproj without XcodeGen or third-party dependencies.

Source membership is explicit in the generated project. Rerun this script after
adding/removing Swift files. Existing Config/Personal.xcconfig is preserved.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "CourtCall.xcodeproj"
OBJECTS: dict[str, dict] = {}


def uid(label: str) -> str:
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()


def add(label: str, isa: str, **values) -> str:
    key = uid(label)
    assert key not in OBJECTS, f"Duplicate project object: {label}"
    OBJECTS[key] = {"isa": isa, **values}
    return key


def scalar(value) -> str:
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def emit(value, depth=0) -> str:
    pad = "\t" * depth
    if isinstance(value, dict):
        rows = ["{"]
        for key, item in value.items():
            rows.append(f"{pad}\t{scalar(key)} = {emit(item, depth + 1)};")
        rows.append(pad + "}")
        return "\n".join(rows)
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "".join(f"{pad}\t{emit(x, depth + 1)},\n" for x in value) + pad + ")"
    return scalar(value)


def file_ref(path: str, filetype: str) -> str:
    key = uid("file:" + path)
    if key in OBJECTS:
        return key
    return add("file:" + path, "PBXFileReference", lastKnownFileType=filetype,
               path=path, sourceTree="<group>")


def group(label: str, name: str, children: list[str]) -> str:
    return add("group:" + label, "PBXGroup", children=children, name=name,
               sourceTree="<group>")


def build_phase(label: str, isa: str, files: list[str], **extra) -> str:
    return add(label, isa, buildActionMask=2147483647, files=files,
               runOnlyForDeploymentPostprocessing=0, **extra)


def build_file(target: str, path: str, ref: str) -> str:
    return add(f"build:{target}:{path}", "PBXBuildFile", fileRef=ref)


def write_plist(path: str, values: dict) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as handle:
        plistlib.dump(values, handle, sort_keys=False)


def scheme(name: str, target: str, product: str) -> None:
    def reference(parent):
        ET.SubElement(parent, "BuildableReference", {
            "BuildableIdentifier": "primary", "BlueprintIdentifier": target,
            "BuildableName": product, "BlueprintName": name,
            "ReferencedContainer": "container:CourtCall.xcodeproj",
        })

    root = ET.Element("Scheme", {"LastUpgradeVersion": "1500", "version": "1.7"})
    build = ET.SubElement(root, "BuildAction", {
        "parallelizeBuildables": "YES", "buildImplicitDependencies": "YES",
    })
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", {
        "buildForTesting": "YES", "buildForRunning": "YES",
        "buildForProfiling": "YES", "buildForArchiving": "YES",
        "buildForAnalyzing": "YES",
    })
    reference(entry)
    ET.SubElement(root, "TestAction", {
        "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB",
        "shouldUseLaunchSchemeArgsEnv": "YES",
    })
    launch = ET.SubElement(root, "LaunchAction", {
        "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB",
        "launchStyle": "0", "useCustomWorkingDirectory": "NO",
        "ignoresPersistentStateOnLaunch": "NO", "debugDocumentVersioning": "YES",
        "debugServiceExtension": "internal", "allowLocationSimulation": "YES",
    })
    reference(ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}))
    profile = ET.SubElement(root, "ProfileAction", {
        "buildConfiguration": "Release", "shouldUseLaunchSchemeArgsEnv": "YES",
        "savedToolIdentifier": "", "useCustomWorkingDirectory": "NO", "debugDocumentVersioning": "YES",
    })
    reference(ET.SubElement(profile, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}))
    ET.SubElement(root, "AnalyzeAction", {"buildConfiguration": "Debug"})
    ET.SubElement(root, "ArchiveAction", {"buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"})
    ET.indent(root)
    destination = PROJECT / "xcshareddata" / "xcschemes" / f"{name}.xcscheme"
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(destination, encoding="UTF-8", xml_declaration=True)


def main() -> None:
    config = ROOT / "Config" / "Personal.xcconfig"
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists():
        config.write_text("// Configure with Scripts/configure_signing.py, or select your Team in Xcode.\n"
                          "COURTCALL_BUNDLE_PREFIX = com.courtcall.personal\n"
                          "DEVELOPMENT_TEAM =\n", encoding="utf-8")
    config_ref = file_ref("Config/Personal.xcconfig", "text.xcconfig")

    common_info = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleDisplayName": "CourtCall", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "ITSAppUsesNonExemptEncryption": False, "UIBackgroundModes": ["audio"],
    }
    write_plist("Apple/iPhone/Info.plist", {
        **common_info, "LSRequiresIPhoneOS": True,
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
        "UILaunchScreen": {"UIColorName": "LaunchBackground"},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    })
    write_plist("Apple/Watch/Info.plist", {
        **common_info, "WKApplication": True,
        "WKCompanionAppBundleIdentifier": "$(COURTCALL_BUNDLE_PREFIX)",
        "WKRunsIndependentlyOfCompanionApp": True,
        "PUICAutoLaunchAudioOptOut": True,
    })

    source_paths = {
        "Core": sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Sources" / "CourtCore").rglob("*.swift")),
        "Session": sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Sources" / "CourtSession").rglob("*.swift")),
        "Shared": sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Apple" / "Shared").rglob("*.swift")),
        "iPhone": sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Apple" / "iPhone").rglob("*.swift")),
        "Watch": sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Apple" / "Watch").rglob("*.swift")),
    }
    refs = {path: file_ref(path, "sourcecode.swift") for paths in source_paths.values() for path in paths}
    for platform in ["iPhone", "Watch"]:
        refs[f"Apple/{platform}/Info.plist"] = file_ref(f"Apple/{platform}/Info.plist", "text.plist.xml")
        refs[f"Apple/{platform}/Assets.xcassets"] = file_ref(f"Apple/{platform}/Assets.xcassets", "folder.assetcatalog")

    product_refs = {
        "CourtCall": add("product:phone", "PBXFileReference", explicitFileType="wrapper.application",
                         includeInIndex=0, path="CourtCall.app", sourceTree="BUILT_PRODUCTS_DIR"),
        "CourtCallWatch": add("product:watch", "PBXFileReference", explicitFileType="wrapper.application",
                              includeInIndex=0, path="CourtCallWatch.app", sourceTree="BUILT_PRODUCTS_DIR"),
    }
    phone_target = uid("target:CourtCall")
    watch_target = uid("target:CourtCallWatch")
    project_id = uid("project")
    proxy = add("watch:proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1,
                remoteGlobalIDString=watch_target, remoteInfo="CourtCallWatch")
    dependency = add("watch:dependency", "PBXTargetDependency", target=watch_target, targetProxy=proxy)
    watch_embed = add("watch:embed", "PBXBuildFile", fileRef=product_refs["CourtCallWatch"],
                      settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
    embed_phase = build_phase("phase:embed-watch", "PBXCopyFilesBuildPhase", [watch_embed],
                              dstPath="$(CONTENTS_FOLDER_PATH)/Watch", dstSubfolderSpec=16,
                              name="Embed Watch Content")

    default_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES", "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES", "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO", "DEVELOPMENT_LANGUAGE": "zh-Hans",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES", "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE", "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES", "SWIFT_VERSION": "5.0",
        "SWIFT_STRICT_CONCURRENCY": "targeted", "SWIFT_EMIT_LOC_STRINGS": "YES",
    }
    project_configs = []
    for name in ["Debug", "Release"]:
        settings = dict(default_settings)
        settings.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
            "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
            "GCC_OPTIMIZATION_LEVEL": "0" if name == "Debug" else "s",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        })
        if name == "Debug":
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = ["DEBUG", "$(inherited)"]
            settings["ONLY_ACTIVE_ARCH"] = "YES"
        project_configs.append(add(f"config:project:{name}", "XCBuildConfiguration", name=name,
                                   baseConfigurationReference=config_ref, buildSettings=settings))
    project_config_list = add("configs:project", "XCConfigurationList", buildConfigurations=project_configs,
                              defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    for target, platform in [("CourtCall", "iPhone"), ("CourtCallWatch", "Watch")]:
        paths = source_paths["Core"] + source_paths["Session"] + source_paths["Shared"] + source_paths[platform]
        source_phase = build_phase(f"phase:{target}:sources", "PBXSourcesBuildPhase",
                                   [build_file(target, path, refs[path]) for path in paths])
        resource = f"Apple/{platform}/Assets.xcassets"
        resource_phase = build_phase(f"phase:{target}:resources", "PBXResourcesBuildPhase",
                                     [build_file(target, resource, refs[resource])])
        framework_phase = build_phase(f"phase:{target}:frameworks", "PBXFrameworksBuildPhase", [])
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": f"Apple/{platform}/Info.plist",
            "MARKETING_VERSION": "0.1.0", "PRODUCT_NAME": "$(TARGET_NAME)",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        }
        if platform == "iPhone":
            settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(COURTCALL_BUNDLE_PREFIX)",
                             "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
                             "SUPPORTED_PLATFORMS": ["iphoneos", "iphonesimulator"],
                             "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                             "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO", "TARGETED_DEVICE_FAMILY": "1"})
        else:
            settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(COURTCALL_BUNDLE_PREFIX).watchkitapp",
                             "WATCHOS_DEPLOYMENT_TARGET": "10.0", "SDKROOT": "watchos", "SKIP_INSTALL": "YES",
                             "SUPPORTED_PLATFORMS": ["watchos", "watchsimulator"], "TARGETED_DEVICE_FAMILY": "4"})
        target_configs = [add(f"config:{target}:{name}", "XCBuildConfiguration", name=name,
                              buildSettings=dict(settings)) for name in ["Debug", "Release"]]
        config_list = add(f"configs:{target}", "XCConfigurationList", buildConfigurations=target_configs,
                          defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
        phases = [source_phase, framework_phase, resource_phase]
        if platform == "iPhone":
            phases.append(embed_phase)
        add("target:" + target, "PBXNativeTarget", name=target, productName=target,
            productReference=product_refs[target], productType="com.apple.product-type.application",
            buildConfigurationList=config_list, buildPhases=phases, buildRules=[],
            dependencies=[dependency] if platform == "iPhone" else [])

    groups = []
    for name in ["Core", "Session", "Shared", "iPhone", "Watch"]:
        children = [refs[path] for path in source_paths[name]]
        if name in ["iPhone", "Watch"]:
            children.extend(refs[f"Apple/{name}/{suffix}"] for suffix in ["Assets.xcassets", "Info.plist"])
        groups.append(group(name, name, children))
    groups.append(group("Configuration", "Configuration", [config_ref]))
    products = group("Products", "Products", list(product_refs.values()))
    main_group = group("main", "CourtCall", groups + [products])
    add("project", "PBXProject", attributes={
        "BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1500",
        "TargetAttributes": {phone_target: {"CreatedOnToolsVersion": "15.0", "ProvisioningStyle": "Automatic"},
                             watch_target: {"CreatedOnToolsVersion": "15.0", "ProvisioningStyle": "Automatic"}},
    }, buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0",
        developmentRegion="zh-Hans", hasScannedForEncodings=0, knownRegions=["zh-Hans", "en", "Base"],
        mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="",
        targets=[phone_target, watch_target])

    # Check every object reference in the constructed graph before serializing it.
    def check(value):
        if isinstance(value, dict):
            for item in value.values():
                check(item)
        elif isinstance(value, list):
            for item in value:
                check(item)
        elif isinstance(value, str) and re.fullmatch(r"[A-F0-9]{24}", value):
            assert value in OBJECTS, f"Dangling PBX object reference {value}"
    check(OBJECTS)
    PROJECT.mkdir(exist_ok=True)
    project_data = {"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                    "objects": OBJECTS, "rootObject": project_id}
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + emit(project_data) + "\n", encoding="utf-8")
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n',
        encoding="utf-8")
    scheme("CourtCall", phone_target, "CourtCall.app")
    scheme("CourtCallWatch", watch_target, "CourtCallWatch.app")
    print("Generated CourtCall.xcodeproj:", ", ".join(f"{key}={len(paths)} Swift files" for key, paths in source_paths.items()))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Erzeugt RideReader.xcodeproj aus den Swift-Dateien der Ordner

  RideReader/         – App
  Shared/             – gemeinsamer Code für App und Widget
  RideReaderWidgets/  – Widget-Erweiterung (Widgets + Live-Aktivität)

Aufruf aus dem Projektordner:  python3 tools/generate_project.py
Nach dem Anlegen oder Löschen von Swift-Dateien erneut ausführen.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def swift_files(folder):
    path = os.path.join(ROOT, folder)
    return sorted(f for f in os.listdir(path) if f.endswith(".swift")) if os.path.isdir(path) else []


app_files = swift_files("RideReader")
shared_files = swift_files("Shared")
widget_files = swift_files("RideReaderWidgets")

_counter = {}


def oid(prefix):
    _counter[prefix] = _counter.get(prefix, 0) + 1
    return f"{prefix}{_counter[prefix]:023X}"


def q(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"' + value.replace('"', '\\"') + '"'


def settings(d):
    return "".join(f"\t\t\t\t{k} = {q(v)};\n" for k, v in sorted(d.items()))


PROJ = oid("A")
APP_TGT, APP_PROD = oid("A"), oid("A")
WID_TGT, WID_PROD = oid("A"), oid("A")
MAIN, APPG, SHAREDG, WIDG, PRODG = oid("B"), oid("B"), oid("B"), oid("B"), oid("B")
APP_SRC, APP_FWK, APP_RES, APP_EMBED = oid("C"), oid("C"), oid("C"), oid("C")
WID_SRC, WID_FWK, WID_RES = oid("C"), oid("C"), oid("C")
PL, APP_TL, WID_TL = oid("D"), oid("D"), oid("D")
PD, PR, AD, AR, WD, WR = (oid("E") for _ in range(6))
PROXY, DEP, EMBED_FILE = oid("7"), oid("7"), oid("7")

# Dateireferenzen (je Ordner) und Build-Dateien (je Ziel)
refs = {}
for folder, files in [("RideReader", app_files), ("Shared", shared_files), ("RideReaderWidgets", widget_files)]:
    for f in files:
        refs[(folder, f)] = oid("F")
app_build = {k: oid("9") for k in [("RideReader", f) for f in app_files] + [("Shared", f) for f in shared_files]}
wid_build = {k: oid("8") for k in [("RideReaderWidgets", f) for f in widget_files] + [("Shared", f) for f in shared_files]}

common = dict(
    ALWAYS_SEARCH_USER_PATHS="NO", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
    COPY_PHASE_STRIP="NO", ENABLE_STRICT_OBJC_MSGSEND="YES", GCC_C_LANGUAGE_STANDARD="gnu17",
    IPHONEOS_DEPLOYMENT_TARGET="16.4", SDKROOT="iphoneos", MTL_FAST_MATH="YES")
project_debug = dict(
    common, DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", GCC_OPTIMIZATION_LEVEL="0",
    ONLY_ACTIVE_ARCH="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", SWIFT_OPTIMIZATION_LEVEL="-Onone")
project_release = dict(
    common, DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", ENABLE_NS_ASSERTIONS="NO",
    SWIFT_COMPILATION_MODE="wholemodule", VALIDATE_PRODUCT="YES")
app_settings = dict(
    CODE_SIGN_STYLE="Automatic", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="1.0",
    DEVELOPMENT_TEAM="", ENABLE_PREVIEWS="YES",
    GENERATE_INFOPLIST_FILE="YES", INFOPLIST_FILE="RideReader/Info.plist",
    INFOPLIST_KEY_CFBundleDisplayName="RideReader",
    INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription="RideReader verbindet sich per Bluetooth mit deinem OBD-Stecker.",
    INFOPLIST_KEY_NSSupportsLiveActivities="YES",
    INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents="YES", INFOPLIST_KEY_UILaunchScreen_Generation="YES",
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone="UIInterfaceOrientationPortrait",
    LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks",
    PRODUCT_BUNDLE_IDENTIFIER="local.ridereader.app", PRODUCT_NAME="$(TARGET_NAME)",
    SWIFT_EMIT_LOC_STRINGS="YES", SWIFT_VERSION="5.0", TARGETED_DEVICE_FAMILY="1")
widget_settings = dict(
    CODE_SIGN_STYLE="Automatic", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="1.0",
    DEVELOPMENT_TEAM="", GENERATE_INFOPLIST_FILE="YES", INFOPLIST_FILE="RideReaderWidgets/Info.plist",
    INFOPLIST_KEY_CFBundleDisplayName="RideReader",
    LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    PRODUCT_BUNDLE_IDENTIFIER="local.ridereader.app.widgets", PRODUCT_NAME="$(TARGET_NAME)",
    SKIP_INSTALL="YES", SWIFT_EMIT_LOC_STRINGS="YES", SWIFT_VERSION="5.0", TARGETED_DEVICE_FAMILY="1")

o = ["// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"]

o.append("/* Begin PBXBuildFile section */\n")
for builds, label in [(app_build, "Sources"), (wid_build, "Sources")]:
    for (folder, f), b in builds.items():
        o.append(f"\t\t{b} /* {f} in {label} */ = {{isa = PBXBuildFile; fileRef = {refs[(folder, f)]} /* {f} */; }};\n")
o.append(f"\t\t{EMBED_FILE} /* RideReaderWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; "
         f"fileRef = {WID_PROD} /* RideReaderWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
o.append("/* End PBXBuildFile section */\n\n")

o.append("/* Begin PBXContainerItemProxy section */\n")
o.append(f"\t\t{PROXY} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {PROJ} /* Project object */;\n"
         f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {WID_TGT};\n\t\t\tremoteInfo = RideReaderWidgets;\n\t\t}};\n")
o.append("/* End PBXContainerItemProxy section */\n\n")

o.append("/* Begin PBXCopyFilesBuildPhase section */\n")
o.append(f"\t\t{APP_EMBED} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
         f"\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{EMBED_FILE} /* RideReaderWidgets.appex in Embed Foundation Extensions */,\n"
         f"\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXCopyFilesBuildPhase section */\n\n")

o.append("/* Begin PBXFileReference section */\n")
o.append(f"\t\t{APP_PROD} /* RideReader.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
         f"includeInIndex = 0; path = RideReader.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
o.append(f"\t\t{WID_PROD} /* RideReaderWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
         f"includeInIndex = 0; path = RideReaderWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
for (folder, f), r in refs.items():
    o.append(f"\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
             f"path = {f}; sourceTree = \"<group>\"; }};\n")
o.append("/* End PBXFileReference section */\n\n")

o.append("/* Begin PBXFrameworksBuildPhase section */\n")
for fwk in (APP_FWK, WID_FWK):
    o.append(f"\t\t{fwk} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
             f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXFrameworksBuildPhase section */\n\n")

o.append("/* Begin PBXGroup section */\n")
o.append(f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APPG} /* RideReader */,\n"
         f"\t\t\t\t{SHAREDG} /* Shared */,\n\t\t\t\t{WIDG} /* RideReaderWidgets */,\n"
         f"\t\t\t\t{PRODG} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
for gid, folder in [(APPG, "RideReader"), (SHAREDG, "Shared"), (WIDG, "RideReaderWidgets")]:
    o.append(f"\t\t{gid} /* {folder} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
             + "".join(f"\t\t\t\t{r} /* {f} */,\n" for (fo, f), r in refs.items() if fo == folder)
             + f"\t\t\t);\n\t\t\tpath = {folder};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{PRODG} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_PROD} /* RideReader.app */,\n"
         f"\t\t\t\t{WID_PROD} /* RideReaderWidgets.appex */,\n"
         f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append("/* End PBXGroup section */\n\n")

o.append("/* Begin PBXNativeTarget section */\n")
o.append(f"\t\t{APP_TGT} /* RideReader */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
         f"\t\t\tbuildConfigurationList = {APP_TL} /* Build configuration list for PBXNativeTarget \"RideReader\" */;\n"
         f"\t\t\tbuildPhases = (\n\t\t\t\t{APP_SRC} /* Sources */,\n\t\t\t\t{APP_FWK} /* Frameworks */,\n\t\t\t\t{APP_RES} /* Resources */,\n"
         f"\t\t\t\t{APP_EMBED} /* Embed Foundation Extensions */,\n"
         f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\t{DEP} /* PBXTargetDependency */,\n\t\t\t);\n"
         f"\t\t\tname = RideReader;\n\t\t\tproductName = RideReader;\n\t\t\tproductReference = {APP_PROD} /* RideReader.app */;\n"
         f"\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};\n")
o.append(f"\t\t{WID_TGT} /* RideReaderWidgets */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
         f"\t\t\tbuildConfigurationList = {WID_TL} /* Build configuration list for PBXNativeTarget \"RideReaderWidgets\" */;\n"
         f"\t\t\tbuildPhases = (\n\t\t\t\t{WID_SRC} /* Sources */,\n\t\t\t\t{WID_FWK} /* Frameworks */,\n\t\t\t\t{WID_RES} /* Resources */,\n"
         f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
         f"\t\t\tname = RideReaderWidgets;\n\t\t\tproductName = RideReaderWidgets;\n\t\t\tproductReference = {WID_PROD} /* RideReaderWidgets.appex */;\n"
         f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t}};\n")
o.append("/* End PBXNativeTarget section */\n\n")

o.append("/* Begin PBXProject section */\n")
o.append(f"\t\t{PROJ} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
         f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1520;\n"
         f"\t\t\t\tLastUpgradeCheck = 1520;\n\t\t\t\tTargetAttributes = {{\n"
         f"\t\t\t\t\t{APP_TGT} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;\n\t\t\t\t\t}};\n"
         f"\t\t\t\t\t{WID_TGT} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;\n\t\t\t\t\t}};\n"
         f"\t\t\t\t}};\n\t\t\t}};\n"
         f"\t\t\tbuildConfigurationList = {PL} /* Build configuration list for PBXProject \"RideReader\" */;\n"
         f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = de;\n\t\t\thasScannedForEncodings = 0;\n"
         f"\t\t\tknownRegions = (\n\t\t\t\tde,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {MAIN};\n"
         f"\t\t\tproductRefGroup = {PRODG} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
         f"\t\t\ttargets = (\n\t\t\t\t{APP_TGT} /* RideReader */,\n\t\t\t\t{WID_TGT} /* RideReaderWidgets */,\n\t\t\t);\n\t\t}};\n")
o.append("/* End PBXProject section */\n\n")

o.append("/* Begin PBXResourcesBuildPhase section */\n")
for res in (APP_RES, WID_RES):
    o.append(f"\t\t{res} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
             f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXResourcesBuildPhase section */\n\n")

o.append("/* Begin PBXSourcesBuildPhase section */\n")
for src, builds in [(APP_SRC, app_build), (WID_SRC, wid_build)]:
    o.append(f"\t\t{src} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
             f"\t\t\tfiles = (\n" + "".join(f"\t\t\t\t{b} /* {f} in Sources */,\n" for (fo, f), b in builds.items())
             + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n")
o.append("/* End PBXSourcesBuildPhase section */\n\n")

o.append("/* Begin PBXTargetDependency section */\n")
o.append(f"\t\t{DEP} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {WID_TGT} /* RideReaderWidgets */;\n"
         f"\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;\n\t\t}};\n")
o.append("/* End PBXTargetDependency section */\n\n")

o.append("/* Begin XCBuildConfiguration section */\n")
for cid, name, s in [(PD, "Debug", project_debug), (PR, "Release", project_release),
                     (AD, "Debug", app_settings), (AR, "Release", app_settings),
                     (WD, "Debug", widget_settings), (WR, "Release", widget_settings)]:
    o.append(f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
             f"{settings(s)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")
o.append("/* End XCBuildConfiguration section */\n\n")

o.append("/* Begin XCConfigurationList section */\n")
for lid, kind, tname, d, r in [(PL, "PBXProject", "RideReader", PD, PR), (APP_TL, "PBXNativeTarget", "RideReader", AD, AR),
                               (WID_TL, "PBXNativeTarget", "RideReaderWidgets", WD, WR)]:
    o.append(f"\t\t{lid} /* Build configuration list for {kind} \"{tname}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n"
             f"\t\t\tbuildConfigurations = (\n\t\t\t\t{d} /* Debug */,\n\t\t\t\t{r} /* Release */,\n\t\t\t);\n"
             f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
o.append(f"/* End XCConfigurationList section */\n\t}};\n\trootObject = {PROJ} /* Project object */;\n}}\n")

out = os.path.join(ROOT, "RideReader.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as fh:
    fh.write("".join(o))
print(f"App: {len(app_files)} · Gemeinsam: {len(shared_files)} · Widget: {len(widget_files)} Swift-Dateien")

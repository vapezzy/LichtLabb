#!/usr/bin/env python3
"""Erzeugt LichtLab.xcodeproj aus allen .swift-Dateien im Ordner LichtLab/.

Aufruf aus dem Projektordner:  python3 tools/generate_project.py
Nach dem Anlegen oder Löschen von Swift-Dateien erneut ausführen.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = sorted(f for f in os.listdir(os.path.join(ROOT, "LichtLab")) if f.endswith(".swift"))


def oid(prefix, n):
    return f"{prefix}{n:023X}"


def q(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"' + value.replace('"', '\\"') + '"'


def settings(d):
    return "".join(f"\t\t\t\t{k} = {q(v)};\n" for k, v in sorted(d.items()))


PROJ, TGT, PROD = oid("A", 1), oid("A", 2), oid("A", 3)
MAIN, APPG, PRODG = oid("B", 1), oid("B", 2), oid("B", 3)
SRC, FWK, RES = oid("C", 1), oid("C", 2), oid("C", 3)
PL, TL = oid("D", 1), oid("D", 2)
PD, PR, TD, TR = oid("E", 1), oid("E", 2), oid("E", 3), oid("E", 4)
refs = {f: (oid("F", i + 1), oid("9", i + 1)) for i, f in enumerate(files)}

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
target = dict(
    CODE_SIGN_STYLE="Automatic", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="0.1",
    DEVELOPMENT_TEAM="", ENABLE_PREVIEWS="YES",
    GENERATE_INFOPLIST_FILE="YES", INFOPLIST_FILE="LichtLab/Info.plist",
    INFOPLIST_KEY_CFBundleDisplayName="LichtLab",
    INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription="LichtLab verbindet sich per Bluetooth mit deinem OBD-Adapter.",
    INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents="YES", INFOPLIST_KEY_UILaunchScreen_Generation="YES",
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone="UIInterfaceOrientationPortrait",
    LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks",
    PRODUCT_BUNDLE_IDENTIFIER="local.lichtlab.f36", PRODUCT_NAME="$(TARGET_NAME)",
    SWIFT_EMIT_LOC_STRINGS="YES", SWIFT_VERSION="5.0", TARGETED_DEVICE_FAMILY="1")

o = ["// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"]
o.append("/* Begin PBXBuildFile section */\n")
for f, (r, b) in refs.items():
    o.append(f"\t\t{b} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {f} */; }};\n")
o.append("/* End PBXBuildFile section */\n\n/* Begin PBXFileReference section */\n")
o.append(f"\t\t{PROD} /* LichtLab.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
         f"includeInIndex = 0; path = LichtLab.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
for f, (r, b) in refs.items():
    o.append(f"\t\t{r} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
             f"path = {f}; sourceTree = \"<group>\"; }};\n")
o.append("/* End PBXFileReference section */\n\n/* Begin PBXFrameworksBuildPhase section */\n")
o.append(f"\t\t{FWK} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
         f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXFrameworksBuildPhase section */\n\n/* Begin PBXGroup section */\n")
o.append(f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APPG} /* LichtLab */,\n"
         f"\t\t\t\t{PRODG} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{APPG} /* LichtLab */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
         + "".join(f"\t\t\t\t{r} /* {f} */,\n" for f, (r, b) in refs.items())
         + "\t\t\t);\n\t\t\tpath = LichtLab;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
o.append(f"\t\t{PRODG} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{PROD} /* LichtLab.app */,\n"
         f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append("/* End PBXGroup section */\n\n/* Begin PBXNativeTarget section */\n")
o.append(f"\t\t{TGT} /* LichtLab */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
         f"\t\t\tbuildConfigurationList = {TL} /* Build configuration list for PBXNativeTarget \"LichtLab\" */;\n"
         f"\t\t\tbuildPhases = (\n\t\t\t\t{SRC} /* Sources */,\n\t\t\t\t{FWK} /* Frameworks */,\n\t\t\t\t{RES} /* Resources */,\n"
         f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = LichtLab;\n"
         f"\t\t\tproductName = LichtLab;\n\t\t\tproductReference = {PROD} /* LichtLab.app */;\n"
         f"\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};\n")
o.append("/* End PBXNativeTarget section */\n\n/* Begin PBXProject section */\n")
o.append(f"\t\t{PROJ} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
         f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1520;\n"
         f"\t\t\t\tLastUpgradeCheck = 1520;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{TGT} = {{\n"
         f"\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;\n\t\t\t\t\t}};\n\t\t\t\t}};\n\t\t\t}};\n"
         f"\t\t\tbuildConfigurationList = {PL} /* Build configuration list for PBXProject \"LichtLab\" */;\n"
         f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = de;\n\t\t\thasScannedForEncodings = 0;\n"
         f"\t\t\tknownRegions = (\n\t\t\t\tde,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {MAIN};\n"
         f"\t\t\tproductRefGroup = {PRODG} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
         f"\t\t\ttargets = (\n\t\t\t\t{TGT} /* LichtLab */,\n\t\t\t);\n\t\t}};\n")
o.append("/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n")
o.append(f"\t\t{RES} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
         f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXSourcesBuildPhase section */\n")
o.append(f"\t\t{SRC} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
         f"\t\t\tfiles = (\n" + "".join(f"\t\t\t\t{b} /* {f} in Sources */,\n" for f, (r, b) in refs.items())
         + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n")
o.append("/* End PBXSourcesBuildPhase section */\n\n/* Begin XCBuildConfiguration section */\n")
for cid, name, s in [(PD, "Debug", project_debug), (PR, "Release", project_release), (TD, "Debug", target), (TR, "Release", target)]:
    o.append(f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
             f"{settings(s)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")
o.append("/* End XCBuildConfiguration section */\n\n/* Begin XCConfigurationList section */\n")
for lid, kind, d, r in [(PL, "PBXProject", PD, PR), (TL, "PBXNativeTarget", TD, TR)]:
    o.append(f"\t\t{lid} /* Build configuration list for {kind} \"LichtLab\" */ = {{\n\t\t\tisa = XCConfigurationList;\n"
             f"\t\t\tbuildConfigurations = (\n\t\t\t\t{d} /* Debug */,\n\t\t\t\t{r} /* Release */,\n\t\t\t);\n"
             f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
o.append(f"/* End XCConfigurationList section */\n\t}};\n\trootObject = {PROJ} /* Project object */;\n}}\n")

out = os.path.join(ROOT, "LichtLab.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as fh:
    fh.write("".join(o))
print(f"{len(files)} Swift-Dateien:", ", ".join(files))

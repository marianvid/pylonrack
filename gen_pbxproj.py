"""
Generates project.pbxproj for PylonRack.
Uses @testable import — tests target does NOT duplicate app sources.
"""

from pathlib import Path

APP_SOURCES = [
    ("AA0001", "AA1001", "PylonRackApp.swift"),
    ("AA0002", "AA1002", "ContentView.swift"),
    ("AA0003", "AA1003", "SettingsStore.swift"),
    ("AA0004", "AA1004", "SystemEnvironment.swift"),
    ("AA0005", "AA1005", "SettingsView.swift"),
    ("AA0006", "AA1006", "Slot.swift"),
    ("AA0007", "AA1007", "SlotStatus.swift"),
    ("AA0008", "AA1008", "SlotManifest.swift"),
    ("AA0009", "AA1009", "SlotConnection.swift"),
    ("AA0010", "AA1010", "SlotProcess.swift"),
    ("AA0011", "AA1011", "SlotRowView.swift"),
    ("AA0012", "AA1012", "RackController.swift"),
    ("AA0013", "AA1013", "RackFolderDelegate.swift"),
    ("AA0014", "AA1014", "RackIconButtonStyle.swift"),
    ("AA0015", "AA1015", "AddSlotView.swift"),
    ("AA0016", "AA1016", "LocalSlotConfig.swift"),
    ("AA0017", "AA1017", "PortFinder.swift"),
    ("AA0018", "AA1018", "LogView.swift"),
    ("AA0019", "AA1019", "StatusBarView.swift"),
    ("AA0020", "AA1020", "SlotControlsView.swift"),
    ("AA0021", "AA1021", "WebViewPanel.swift"),
]

APP_RESOURCES = [
    ("AA0030", "AA1030", "Assets.xcassets", "folder.assetcatalog"),
    ("AA0031", "AA1031", "PylonRack.icns",  "image.icns"),
]

TEST_SOURCES = [
    ("BB0001", "BB1001", "PylonRackTests.swift"),
    ("BB0002", "BB1002", "MockWSServer.swift"),
    ("BB0003", "BB1003", "SettingsStoreTests.swift"),
    ("BB0004", "BB1004", "SlotManifestTests.swift"),
    ("BB0005", "BB1005", "IncomingMessageTests.swift"),
    ("BB0006", "BB1006", "SlotConnectionTests.swift"),
    ("BB0007", "BB1007", "RackControllerTests.swift"),
]

NETWORK_BF = "BB0010"
NETWORK_FR = "BB1010"


def pbx():
    lines = []

    def ln(s=""): lines.append(s)

    ln("// !$*UTF8*$!")
    ln("{")
    ln("\tarchiveVersion = 1;")
    ln("\tclasses = { };")
    ln("\tobjectVersion = 56;")
    ln("\tobjects = {")
    ln()

    # PBXBuildFile
    ln("/* Begin PBXBuildFile section */")
    for bf, fr, name in APP_SOURCES:
        ln(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {fr}; }};")
    for bf, fr, name, _ in APP_RESOURCES:
        ln(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {fr}; }};")
    for bf, fr, name in TEST_SOURCES:
        ln(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {fr}; }};")
    ln(f"\t\t{NETWORK_BF} = {{isa = PBXBuildFile; fileRef = {NETWORK_FR}; }};")
    ln("/* End PBXBuildFile section */")
    ln()

    # PBXFileReference
    ln("/* Begin PBXFileReference section */")
    ln('\t\tAA0099 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PylonRack.app; sourceTree = BUILT_PRODUCTS_DIR; };')
    for bf, fr, name in APP_SOURCES:
        ln(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};')
    for bf, fr, name, kind in APP_RESOURCES:
        ln(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = {name}; sourceTree = "<group>"; }};')
    ln('\t\tBB0099 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PylonRackTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };')
    for bf, fr, name in TEST_SOURCES:
        ln(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};')
    ln(f'\t\t{NETWORK_FR} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Network.framework; path = System/Library/Frameworks/Network.framework; sourceTree = SDKROOT; }};')
    ln("/* End PBXFileReference section */")
    ln()

    # PBXFrameworksBuildPhase
    ln("/* Begin PBXFrameworksBuildPhase section */")
    ln("\t\tAA_FW = { isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };")
    ln(f"\t\tBB_FW = {{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({NETWORK_BF},); runOnlyForDeploymentPostprocessing = 0; }};")
    ln("/* End PBXFrameworksBuildPhase section */")
    ln()

    # PBXGroup
    ln("/* Begin PBXGroup section */")
    ln("\t\tROOT_GRP = {")
    ln("\t\t\tisa = PBXGroup;")
    ln("\t\t\tchildren = (APP_GRP, TEST_GRP, FW_GRP, PROD_GRP,);")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t};")
    ln("\t\tPROD_GRP = { isa = PBXGroup; children = (AA0099, BB0099,); name = Products; sourceTree = \"<group>\"; };")

    # App group
    app_children = ", ".join(fr for _, fr, _ in APP_SOURCES) + ", " + ", ".join(fr for _, fr, _, _ in APP_RESOURCES)
    ln("\t\tAPP_GRP = {")
    ln("\t\t\tisa = PBXGroup;")
    ln(f"\t\t\tchildren = ({app_children},);")
    ln("\t\t\tpath = PylonRack;")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t};")

    # Test group
    test_children = ", ".join(fr for _, fr, _ in TEST_SOURCES)
    ln("\t\tTEST_GRP = {")
    ln("\t\t\tisa = PBXGroup;")
    ln(f"\t\t\tchildren = ({test_children},);")
    ln("\t\t\tpath = PylonRackTests;")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t};")

    ln(f"\t\tFW_GRP = {{ isa = PBXGroup; children = ({NETWORK_FR},); name = Frameworks; sourceTree = \"<group>\"; }};")
    ln("/* End PBXGroup section */")
    ln()

    # PBXNativeTarget
    ln("/* Begin PBXNativeTarget section */")
    ln("\t\tAA_TGT = {")
    ln("\t\t\tisa = PBXNativeTarget;")
    ln("\t\t\tbuildConfigurationList = AA_CFGLIST;")
    ln("\t\t\tbuildPhases = (AA_SRC, AA_FW, AA_RES,);")
    ln("\t\t\tbuildRules = ();")
    ln("\t\t\tdependencies = ();")
    ln("\t\t\tname = PylonRack;")
    ln("\t\t\tproductName = PylonRack;")
    ln("\t\t\tproductReference = AA0099;")
    ln('\t\t\tproductType = "com.apple.product-type.application";')
    ln("\t\t};")
    ln("\t\tBB_TGT = {")
    ln("\t\t\tisa = PBXNativeTarget;")
    ln("\t\t\tbuildConfigurationList = BB_CFGLIST;")
    ln("\t\t\tbuildPhases = (BB_SRC, BB_FW,);")
    ln("\t\t\tbuildRules = ();")
    ln("\t\t\tdependencies = ();")
    ln("\t\t\tname = PylonRackTests;")
    ln("\t\t\tproductName = PylonRackTests;")
    ln("\t\t\tproductReference = BB0099;")
    ln('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
    ln("\t\t};")
    ln("/* End PBXNativeTarget section */")
    ln()

    # PBXProject
    ln("/* Begin PBXProject section */")
    ln("\t\tPROJECT = {")
    ln("\t\t\tisa = PBXProject;")
    ln("\t\t\tattributes = {")
    ln("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    ln("\t\t\t\tLastSwiftUpdateCheck = 1540;")
    ln("\t\t\t\tLastUpgradeCheck = 1540;")
    ln("\t\t\t\tTargetAttributes = {")
    ln("\t\t\t\t\tAA_TGT = { CreatedOnToolsVersion = 15.4; };")
    ln("\t\t\t\t\tBB_TGT = { CreatedOnToolsVersion = 15.4; TestTargetID = AA_TGT; };")
    ln("\t\t\t\t};")
    ln("\t\t\t};")
    ln("\t\t\tbuildConfigurationList = PROJ_CFGLIST;")
    ln('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    ln("\t\t\tdevelopmentRegion = en;")
    ln("\t\t\thasScannedForEncodings = 0;")
    ln("\t\t\tknownRegions = (en, Base,);")
    ln("\t\t\tmainGroup = ROOT_GRP;")
    ln("\t\t\tproductRefGroup = PROD_GRP;")
    ln('\t\t\tprojectDirPath = "";')
    ln('\t\t\tprojectRoot = "";')
    ln("\t\t\ttargets = (AA_TGT, BB_TGT,);")
    ln("\t\t};")
    ln("/* End PBXProject section */")
    ln()

    # PBXResourcesBuildPhase
    ln("/* Begin PBXResourcesBuildPhase section */")
    res_files = ", ".join(bf for bf, _, _, _ in APP_RESOURCES)
    ln(f"\t\tAA_RES = {{ isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({res_files},); runOnlyForDeploymentPostprocessing = 0; }};")
    ln("/* End PBXResourcesBuildPhase section */")
    ln()

    # PBXSourcesBuildPhase
    ln("/* Begin PBXSourcesBuildPhase section */")
    app_bf = ", ".join(bf for bf, _, _ in APP_SOURCES)
    ln(f"\t\tAA_SRC = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({app_bf},); runOnlyForDeploymentPostprocessing = 0; }};")
    test_bf = ", ".join(bf for bf, _, _ in TEST_SOURCES)
    ln(f"\t\tBB_SRC = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({test_bf},); runOnlyForDeploymentPostprocessing = 0; }};")
    ln("/* End PBXSourcesBuildPhase section */")
    ln()

    # XCBuildConfiguration
    ln("/* Begin XCBuildConfiguration section */")

    # Project-level debug
    ln("\t\tPROJ_DBG = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    ln("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    ln("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    ln("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    ln('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
    ln("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    ln('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)",);')
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    ln("\t\t\t\tSDKROOT = macosx;")
    ln('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
    ln('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    ln("\t\t\t};")
    ln('\t\t\tname = Debug;')
    ln("\t\t};")

    # Project-level release
    ln("\t\tPROJ_REL = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    ln("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    ln("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    ln("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    ln('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
    ln("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tSDKROOT = macosx;")
    ln('\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;')
    ln("\t\t\t};")
    ln('\t\t\tname = Release;')
    ln("\t\t};")

    # App debug
    ln("\t\tAA_DBG = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tASETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    ln("\t\t\t\tASETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    ln("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    ln("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    ln("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    ln('\t\t\t\tDEVELOPMENT_TEAM = "";')
    ln("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    ln("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    ln("\t\t\t\tINFOPLIST_FILE = PylonRack/Info.plist;")
    ln("\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;")
    ln("\t\t\t\tINFOPLIST_KEY_NSPrincipalClass = NSApplication;")
    ln('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks",);')
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tMARKETING_VERSION = 1.0;")
    ln('\t\t\t\tOTHER_LDFLAGS = ("-framework", "WebKit",);')
    ln("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marianvid.pylonrack;")
    ln('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    ln("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    ln("\t\t\t\tSWIFT_VERSION = 5.0;")
    ln("\t\t\t};")
    ln('\t\t\tname = Debug;')
    ln("\t\t};")

    # App release (same as debug for our purposes)
    ln("\t\tAA_REL = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tASETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    ln("\t\t\t\tASETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    ln("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    ln("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    ln("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    ln('\t\t\t\tDEVELOPMENT_TEAM = "";')
    ln("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    ln("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    ln("\t\t\t\tINFOPLIST_FILE = PylonRack/Info.plist;")
    ln("\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;")
    ln("\t\t\t\tINFOPLIST_KEY_NSPrincipalClass = NSApplication;")
    ln('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks",);')
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tMARKETING_VERSION = 1.0;")
    ln('\t\t\t\tOTHER_LDFLAGS = ("-framework", "WebKit",);')
    ln("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marianvid.pylonrack;")
    ln('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    ln("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    ln("\t\t\t\tSWIFT_VERSION = 5.0;")
    ln("\t\t\t};")
    ln('\t\t\tname = Release;')
    ln("\t\t};")

    # Tests debug
    ln("\t\tBB_DBG = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    ln('\t\t\t\tDEVELOPMENT_TEAM = "";')
    ln("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    ln('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@loader_path/../Frameworks",);')
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marianvid.pylonrack.tests;")
    ln('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    ln("\t\t\t\tSDKROOT = macosx;")
    ln("\t\t\t\tSWIFT_VERSION = 5.0;")
    ln('\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/PylonRack.app/Contents/MacOS/PylonRack";')
    ln('\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";')
    ln("\t\t\t};")
    ln('\t\t\tname = Debug;')
    ln("\t\t};")

    # Tests release
    ln("\t\tBB_REL = {")
    ln("\t\t\tisa = XCBuildConfiguration;")
    ln("\t\t\tbuildSettings = {")
    ln("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    ln('\t\t\t\tDEVELOPMENT_TEAM = "";')
    ln("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    ln('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@loader_path/../Frameworks",);')
    ln("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    ln("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marianvid.pylonrack.tests;")
    ln('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    ln("\t\t\t\tSDKROOT = macosx;")
    ln("\t\t\t\tSWIFT_VERSION = 5.0;")
    ln('\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/PylonRack.app/Contents/MacOS/PylonRack";')
    ln('\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";')
    ln("\t\t\t};")
    ln('\t\t\tname = Release;')
    ln("\t\t};")

    ln("/* End XCBuildConfiguration section */")
    ln()

    # XCConfigurationList
    ln("/* Begin XCConfigurationList section */")
    ln("\t\tPROJ_CFGLIST = { isa = XCConfigurationList; buildConfigurations = (PROJ_DBG, PROJ_REL,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };")
    ln("\t\tAA_CFGLIST = { isa = XCConfigurationList; buildConfigurations = (AA_DBG, AA_REL,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };")
    ln("\t\tBB_CFGLIST = { isa = XCConfigurationList; buildConfigurations = (BB_DBG, BB_REL,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };")
    ln("/* End XCConfigurationList section */")
    ln()

    ln("\t};")
    ln("\trootObject = PROJECT;")
    ln("}")

    return "\n".join(lines)


out = Path("/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj")
out.write_text(pbx(), encoding="utf-8")
print("Written", out)
print("Lines:", len(out.read_text().splitlines()))

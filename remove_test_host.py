from pathlib import Path
import re

p = Path('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj')
c = p.read_text()

# Remove TEST_HOST and BUNDLE_LOADER lines
c = re.sub(r'\t\t\t\tTEST_HOST = "[^"]*";\n', '', c)
c = re.sub(r'\t\t\t\tBUNDLE_LOADER = "[^"]*";\n', '', c)

p.write_text(c)
print("Done")
print("TEST_HOST remaining:", 'TEST_HOST' in c)
print("BUNDLE_LOADER remaining:", 'BUNDLE_LOADER' in c)

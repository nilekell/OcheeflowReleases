#!/bin/sh

# retrieve static environment variables
source ./env_vars.sh
export PROJECT_NAME PROJECT_PATH GENERAL_RELEASES_PATH OCHEEFLOW_RELEASES_REPO XCODE_DERIVED_DATA_PATH
export OLD_APPCAST_URL NEW_APPCAST_URL
export GITHUB_PAT_PATH APPLE_CODESIGN_IDENTITY APPLE_ID APPLE_NOTARY_PASSWORD APPLE_TEAM_ID

# function check if command fails
check_exit_status() {
    local exit_code=$?
    if [[ $exit_code -eq 1 ]]; then
        echo "$1"
        exit $exit_code
    else
        echo "$2"
    fi
}

# authenticate with github cli
export GITHUB_TOKEN=$(echo $(cat "${GITHUB_PAT_PATH}"))

check_exit_status "Failed to find Github Personal Access Token at: ${GITHUB_PAT_PATH}" "Exported env [${GITHUB_PAT_PATH}] to environment. Logged into Github CLI."

cd "${PROJECT_PATH}"

check_exit_status "Failed to change directory to: ${PROJECT_PATH}" "Changed directory to: ${PROJECT_PATH}"

git checkout dev && git pull

check_exit_status "Failed to checkout dev branch for repository ${PROJECT_PATH}" "Checked out dev branch for ${PROJECT_PATH}"

# increment version and build number
python3 <<EOF
import os
import re

# Path to the project file
project_path = os.getenv('PROJECT_PATH')
project_name = os.getenv('PROJECT_NAME')
file_path = os.path.join(project_path, f'{project_name}.xcodeproj', 'project.pbxproj')

# Read the file content
with open(file_path, 'r', encoding='utf-8') as file:
    content = file.read()

# Pattern for CURRENT_PROJECT_VERSION = x
current_version_pattern = r'(CURRENT_PROJECT_VERSION\s*=\s*)(\d+)(;)'
# Increment CURRENT_PROJECT_VERSION by 1
content = re.sub(current_version_pattern, lambda match: f"{match.group(1)}{int(match.group(2)) + 1}{match.group(3)}", content)

# Pattern for MARKETING_VERSION = x.x
marketing_version_pattern = r'(MARKETING_VERSION\s*=\s*)(\d+\.\d+)(;)'
# Increment MARKETING_VERSION by 0.1
content = re.sub(marketing_version_pattern, lambda match: f"{match.group(1)}{round(float(match.group(2)) + 0.1, 1)}{match.group(3)}", content)

# Write the updated content back to the file
with open(file_path, 'w', encoding='utf-8') as file:
    file.write(content)
EOF

# computed variables
export VERSION=v$(sed -n '/MARKETING_VERSION/{s/MARKETING_VERSION = //;s/;//;s/^[[:space:]]*//;p;q;}' "${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj")
export BUILD_NUMBER=$(xcrun agvtool what-version -terse)

check_exit_status "Failed to increment version and/or build number in: ${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj" "Incremented version and build number to ${VERSION} [${BUILD_NUMBER}] in: ${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

# Stage version & build number changes
git add "${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

check_exit_status "Failed to stage: "${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj"" "Staged project version changes successfully: "${PROJECT_PATH}/${PROJECT_NAME}.xcodeproj/project.pbxproj""

# Commit the changes with the commit message
git commit -m "upgrade version to ${VERSION} [${BUILD_NUMBER}]"

check_exit_status "Failed to commit version changes" "Committed version changes successfully"

# Push changes to the dev branch
git push origin dev

check_exit_status "Failed to push changes to dev branch" "Pushed changes to dev branch successfully"

# Create a pull request from dev to main
gh pr create --title "Upgrade version to ${VERSION} [${BUILD_NUMBER}]" --body "This PR upgrades the project version to ${VERSION} and build number ${BUILD_NUMBER}." --base main --head dev

check_exit_status "Failed to create a pull request from dev to main" "Created a pull request from dev to main successfully"

# Merge the pull request
gh pr merge --auto --squash

check_exit_status "Failed to merge the pull request" "Merged the pull request successfully"

# Final message indicating success
echo "Version upgrade to ${VERSION} [${BUILD_NUMBER}] has been successfully committed, pushed, and merged into main."

# computed path variables
export ARCHIVE_DESTINATION="${GENERAL_RELEASES_PATH}/Archives/${VERSION}/"
export ARCHIVE_PATH="${ARCHIVE_DESTINATION}/${PROJECT_NAME}.xcarchive"
export XCODE_OCHEEFLOW_DERIVED_DATA_PATH="${XCODE_DERIVED_DATA_PATH}/${PROJECT_NAME}-cxkmslyjxofopffnjutfwsxjyoes"
export BUILD_CONTEXT_PATH="${OCHEEFLOW_RELEASES_REPO}/build"
export RELEASE_DESTINATION="${GENERAL_RELEASES_PATH}/${PROJECT_NAME}_${VERSION}/"
export APP_RELEASE_PATH="${RELEASE_DESTINATION}/${PROJECT_NAME}.app"
export DMG_RELEASE_PATH="${RELEASE_DESTINATION}/${PROJECT_NAME}.dmg"

git checkout main && git pull

check_exit_status "Failed to checkout main branch for repository ${PROJECT_PATH}" "Checked out main branch for ${PROJECT_PATH}"

xcodebuild -scheme ${PROJECT_NAME} clean

check_exit_status "Failed to clean Xcode" "Cleaned Xcode"

rm -rf "${XCODE_DERIVED_DATA_PATH}"

check_exit_status "Failed to delete Xcode Derived Data: ${XCODE_DERIVED_DATA_PATH}" "Deleted Xcode Derived Data at: ${XCODE_DERIVED_DATA_PATH}"

echo "Building version: ${VERSION} [${BUILD_NUMBER}] ..."

# builds archive file from scheme
xcodebuild archive -scheme "${PROJECT_NAME}" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}"

check_exit_status "Failed to build archive ${ARCHIVE_PATH}" "Built archive [archive: ${ARCHIVE_PATH}] from scheme"

# create ExportOptions.plist to be ingested
cp "${BUILD_CONTEXT_PATH}/ExportOptionsTemplate.plist" "${BUILD_CONTEXT_PATH}/ExportOptions.plist"

check_exit_status "Failed to copy: ${BUILD_CONTEXT_PATH}/ExportOptionsTemplate.plist -> ${BUILD_CONTEXT_PATH}/ExportOptions.plist" "Copied ${BUILD_CONTEXT_PATH}/ExportOptionsTemplate.plist -> ${BUILD_CONTEXT_PATH}/ExportOptions.plist"

# update the teamID in ExportOptions.plist using regex
python3 <<EOF
import re
import os

# Define the old and new strings
old_string = '#TEAM_ID#'
new_string = os.getenv('APPLE_TEAM_ID')

build_context_path = os.getenv('BUILD_CONTEXT_PATH')
plist_path = build_context_path + '/' + 'ExportOptions.plist'

# Open the file in read mode and read its contents
with open(plist_path, 'r', encoding='utf-8') as file:
    file_content = file.read()

# Replace the old string with the new string
new_content = file_content.replace(old_string, new_string)

# Open the file in write mode and write the updated content
with open(plist_path, 'w', encoding='utf-8') as file:
    file.write(new_content)
EOF

check_exit_status "Failed to replace teamId in: ${BUILD_CONTEXT_PATH}/ExportOptions.plist" "Updated teamId from '#TEAM_ID#' to ${APPLE_TEAM_ID} in: ${BUILD_CONTEXT_PATH}/ExportOptions.plist"

mkdir -p ${ARCHIVE_DESTINATION}
# export archive
xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${BUILD_CONTEXT_PATH}/ExportOptions.plist"

check_exit_status "Failed to export archive ${ARCHIVE_PATH}" "Exported archive to ${ARCHIVE_PATH}"

# cleanup ExportOptions.plist with real values
rm "${BUILD_CONTEXT_PATH}/ExportOptions.plist"

check_exit_status "Failed to delete archive ${BUILD_CONTEXT_PATH}/ExportOptions.plist" "Deleted ${BUILD_CONTEXT_PATH}/ExportOptions.plist"

# send archive to notarization service
# wait until apple finishes notarization
# export app bundle
mkdir -p ${RELEASE_DESTINATION}

check_exit_status "Failed to create directory: ${RELEASE_DESTINATION}" "Created directory: ${RELEASE_DESTINATION}"

echo "Uploading archive to Apple notarization service..."

until xcodebuild \
    -exportNotarizedApp \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${RELEASE_DESTINATION}"; \
do \
   echo wait 10s...; \
   sleep 10; \
done

check_exit_status "Failed to notarize archive: ${ARCHIVE_PATH}" "Notarized archive ${ARCHIVE_PATH}"

cd "${GENERAL_RELEASES_PATH}"
# create empty dmg
hdiutil create -size 100m -fs APFS -volname "${PROJECT_NAME}" "${DMG_RELEASE_PATH}"

check_exit_status "Failed to created empty DMG: ${DMG_RELEASE_PATH}" "Created empty DMG: ${DMG_RELEASE_PATH}"

# create dmg file
dmgcanvas \
    "${BUILD_CONTEXT_PATH}/DMGCanvas_Ocheeflow.dmgcanvas/" \
    "${DMG_RELEASE_PATH}" \
    -setFilePath "${PROJECT_NAME}.app" "${APP_RELEASE_PATH}" \
    -volumeName "${PROJECT_NAME}" \
    -volumeIcon "${BUILD_CONTEXT_PATH}/volume_rounded.png" \
    -backgroundImage "${BUILD_CONTEXT_PATH}/installer_background.png" \
    -identity "${APPLE_CODESIGN_IDENTITY}" \
    -notarizationAppleID "${APPLE_ID}" \
    -notarizationPassword "${APPLE_NOTARY_PASSWORD}" \
    -notarizationTeamID "${APPLE_TEAM_ID}"
    
check_exit_status "Failed to created & notarize: ${DMG_RELEASE_PATH}" "Created & notarized: ${DMG_RELEASE_PATH}"

# generate sparkle appcast
${XCODE_OCHEEFLOW_DERIVED_DATA_PATH}/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast ${RELEASE_DESTINATION}

check_exit_status "Failed to generate: ${RELEASE_DESTINATION}/appcast.xml" "Generated: ${RELEASE_DESTINATION}/appcast.xml"

# replace url in appcast.xml
python3 <<EOF
import os
import re

# Define the paths and URLs
file_path = os.path.join(os.getenv('RELEASE_DESTINATION'), 'appcast.xml')
old_url = os.getenv('OLD_APPCAST_URL')
new_url = os.getenv('NEW_APPCAST_URL')

# Read the XML file as a regular text file
with open(file_path, 'r', encoding='utf-8') as file:
    content = file.read()

# Use regex to find and replace the URL in the enclosure tag
pattern = re.compile(r'(enclosure\s+[^>]*url=\")' + re.escape(old_url) + r'(\"[^>]*>)')
new_content = pattern.sub(r'\1' + new_url + r'\2', content)

# Check if any replacement was made
if old_url in content:
    print(f'Replaced URL: {old_url} with {new_url}')
else:
    print('URL not found or already updated.')

# Write the modified content back to the file
with open(file_path, 'w', encoding='utf-8') as file:
    file.write(new_content)
EOF

check_exit_status "Failed to replace URL in: ${RELEASE_DESTINATION}/appcast.xml" "Replaced URL in: ${RELEASE_DESTINATION}/appcast.xml"

cd "${OCHEEFLOW_RELEASES_REPO}"

check_exit_status "Failed to change directory to: ${OCHEEFLOW_RELEASES_REPO}" "Changed directory to: ${OCHEEFLOW_RELEASES_REPO}"

# update github release title
gh release edit prod --title ${VERSION} --latest

check_exit_status "Failed to update GitHub release title to: ${VERSION}" "Updated GitHub release title to: ${VERSION}"

# update github release dmg asset
gh release upload prod "${DMG_RELEASE_PATH}" --clobber

check_exit_status "Failed to upload GitHub release DMG asset: ${DMG_RELEASE_PATH}" "Uploaded ${DMG_RELEASE_PATH} to GitHub release DMG asset"

# copy appcast.xml from OcheeflowReleases/Ocheeflow_vx.x -> OcheeflowReleases/repo/OcheeflowReleases/appcast.xml
cp "${RELEASE_DESTINATION}/appcast.xml" "${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

check_exit_status "Failed to copy: ${RELEASE_DESTINATION}/appcast.xml -> ${OCHEEFLOW_RELEASES_REPO}/appcast.xml" "Copied ${RELEASE_DESTINATION}/appcast.xml -> ${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

# update OcheeflowReleases repo appcast.xml
git add "${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

check_exit_status "Failed to stage ${OCHEEFLOW_RELEASES_REPO}/appcast.xml" "Added: ${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

git commit -m "add ${VERSION} [${BUILD_NUMBER}] appcast.xml"

check_exit_status "Failed to commit ${OCHEEFLOW_RELEASES_REPO}/appcast.xml" "Committed: ${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

git push origin main

check_exit_status "Failed to push ${OCHEEFLOW_RELEASES_REPO}/appcast.xml" "Pushed: ${OCHEEFLOW_RELEASES_REPO}/appcast.xml"

# force-update the 'prod' tag to point to the latest commit on the 'main' branch
git tag -f prod main

check_exit_status "Failed to update 'prod' tag to the latest commit on 'main' branch" "Updated 'prod' tag to latest commit on 'main' branch"

git push origin prod --force

check_exit_status "Failed to push prod tag to origin" "Pushed prod tag to origin successfully"

echo "All steps completed successfully! The ${VERSION} [${BUILD_NUMBER}] release has been built, notarized, and uploaded. The production tag is now up to date."

exit 0
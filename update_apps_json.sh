#!/bin/bash

# Set environment variables with default values if not already set
export VERSION_IPA="${VERSION_IPA:-0.0.0}"
export VERSION_DATE="${VERSION_DATE:-2000-12-18T00:00:00Z}"
export BETA="${BETA:-true}"
export COMMIT_ID="${COMMIT_ID:-1234567}"
export SIZE="${SIZE:-0}"
export SHA256="${SHA256:-}"
export LOCALIZED_DESCRIPTION="${LOCALIZED_DESCRIPTION:-Invalid Update}"
export DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/SideStore/SideStore/releases/download/0.0.0/SideStore.ipa}"

echo "Input File: $1"

# Debugging the environment variables
echo "Version: $VERSION_IPA"
echo "Version Date: $VERSION_DATE"
echo "Beta: $BETA"
echo "Commit ID: $COMMIT_ID"
echo "Size: $SIZE"
echo "Sha256: $SHA256"
echo "Localized Description: $LOCALIZED_DESCRIPTION"
echo "Download URL: $DOWNLOAD_URL"

# Perform jq operation
UPDATED_JSON=$(cat "${1}" | jq --arg bundleIdentifier "com.SideStore.SideStore" \
    --arg version "$VERSION_IPA" \
    --arg versionDate "$VERSION_DATE" \
    --arg beta "$BETA" \
    --arg commitID "$COMMIT_ID" \
    --arg size "$SIZE" \
    --arg sha256 "$SHA256" \
    --arg localizedDescription "$(echo $LOCALIZED_DESCRIPTION | jq -Rs .)" \
    --arg downloadURL "$DOWNLOAD_URL" \
    --arg versionDescription "$(echo $VERSION_DESCRIPTION | jq -Rs .)" \
    '
        .apps |= map(
            if .bundleIdentifier == $bundleIdentifier then
                .version = $version |
                .versionDate = $versionDate |
                .beta = ($beta == "true") |
                .commitID = $commitID |
                .size = ($size | tonumber) |
                .sha256 = $sha256 |
                .localizedDescription = $localizedDescription |
                .downloadURL = $downloadURL |

                if (.versions | length > 0) and 
                   ((.versions[0].version != $version) or (.versions[0].beta != ($beta == "true"))) then
                    .versions |= (
                        [{ "version": $version, 
                           "date": $versionDate, 
                           "localizedDescription": $localizedDescription, 
                           "downloadURL": $downloadURL, 
                           "beta": ($beta == "true"), 
                           "commitID": $commitID, 
                           "size": ($size | tonumber),
                           "sha256": $sha256
                        }] + 
                        . 
                        # | map(
                        #     if .sha256 == null then
                        #         (. + {sha256: $sha256})
                        #     else
                        #         .
                        #     end
                        # )
                    )
                else
                    .
                end
            else
                .
            end
        )
    '
)

# Check if jq failed and print result
if [ $? -eq 0 ]; then
    echo "Updated JSON:"
    echo "$UPDATED_JSON"
    echo "$UPDATED_JSON" > "${1}"
else
    echo "Error in jq processing."
fi

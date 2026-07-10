#!/bin/bash

# 1. Define the list of server IPs (Use space to separate, no commas)
SERVERS=("10.102.15.52" "10.102.15.68" "10.102.15.67" "10.102.15.66" "10.102.15.65" "10.102.15.70" "10.102.15.72" "10.102.15.34" "10.102.15.42" "10.102.15.58")

# 2. Define variables for easier management
SSH_PASS='SanFrancisc0Hitch!'
CERT_PASS='DJcFnFld8h66dSUw3aT7Y'
# Using $HOME instead of ~ to avoid path resolution issues in scripts
ZIP_FILE="$HOME/Downloads/DCWC_Dev_Resources_042826.zip"
REMOTE_USER="sfo-build"

# 3. Loop through each server one by one
for IP in "${SERVERS[@]}"
do
    # Remove any accidental trailing commas or whitespace from the IP string
    IP=$(echo $IP | tr -d '[:space:],')

    echo "----------------------------------------------------------"
    echo "🚀 Processing server: $IP"
    echo "----------------------------------------------------------"

    # Check if the local zip file exists before attempting upload
    if [ ! -f "$ZIP_FILE" ]; then
        echo "❌ Error: Local file not found at $ZIP_FILE"
        exit 1
    fi

    # Upload the zip file to the remote server's home directory
    echo "📤 Uploading file to $IP..."
    sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no "$ZIP_FILE" "$REMOTE_USER@$IP:~/"

    # Proceed with installation only if the upload was successful
    if [ $? -eq 0 ]; then
        echo "⚙️ Executing installation commands on $IP..."
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$IP" "
            # Extract the main resource zip
            unzip -o ~/DCWC_Dev_Resources_042826.zip -d ~/update_ios_temp;
            cd ~/update_ios_temp/DCWC_Dev_Resources_042826;

            # Unlock the Keychain (required for certificate manipulation via SSH)
            security unlock-keychain -p '$SSH_PASS' ~/Library/Keychains/login.keychain-db;
            
            # Extract the internal certificate zip
            unzip -o WB_Dev_26-27.zip -d ./;
            
            # Import the .p12 Certificate into the keychain
            security import WB_Dev_26-27.p12 -k ~/Library/Keychains/login.keychain-db -P '$CERT_PASS' -T /usr/bin/codesign;
            
            # Configure access rights to prevent the 'codesign' UI popup during builds
            security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '$SSH_PASS' ~/Library/Keychains/login.keychain-db;
            
            # Install the Provisioning Profile to the standard iOS path
            mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles/;
            cp DCWC_Dev.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/;
            
            # Clean up temporary files to keep the server tidy
            rm -rf ~/update_ios_temp ~/DCWC_Dev_Resources_042826.zip;

            echo '✅ Installation completed on $IP';
            # Verify the certificate installation
            security find-identity -p codesigning -v | grep 'Matching identities';
        "
    else
        echo "❌ Failed to upload file to $IP. Skipping to next server..."
    fi
done

echo "🎉 All servers in the list have been processed!"
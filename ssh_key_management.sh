#!/bin/bash
##############################################
# SSH Key Management Script
# Purpose: Validate and deploy SSH key pairs
# Features:
# - Strict permission enforcement
# - Clear filename conflict reporting
# - Secure key handling
# - Proper key pair validation
# Configuration loaded from ssh_manager_config.env file
##############################################

# Determine the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/ssh_manager_config.env"
CONFIG_EXAMPLES=$(cat << 'EOF'
Examples:
         SRC_DIR=/path/to/source_directory/.ssh
         SSH_DIR=/path/to/ssh_directory/.ssh
         KEY_COMMENT=user@example.com
         KEY_TYPE=rsa
         KEY_BITS=4096
EOF
)

# Function to validate .env and configuration variables
validate_config() {
    # Check if ssh_manager_config.env exists and source it
    if [ -f "$ENV_FILE" ]; then
        # Export variables from ssh_manager_config.env, ignoring comments and empty lines
        while IFS='=' read -r key value; do
            # Skip lines that are empty or start with #
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            # Remove leading/trailing whitespace from key and value
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            # Export the variable if both key and value are non-empty
            [[ -n "$key" && -n "$value" ]] && export "$key"="$value"
        done < "$ENV_FILE"
    else
        echo "ERROR: Configuration file (ssh_manager_config.env) not found"
        echo "       Expected: '$ENV_FILE'"
        echo "       Please create it with the required variables"
        echo "       $CONFIG_EXAMPLES"
        exit 1
    fi

    # Configuration Variables (loaded from ssh_manager_config.env - no defaults)
    SRC_DIR="$SRC_DIR"
    SSH_DIR="$SSH_DIR"
    KEY_COMMENT="$KEY_COMMENT"
    KEY_TYPE="$KEY_TYPE"
    KEY_BITS="$KEY_BITS"

    # Validate required variables
    for var in SRC_DIR SSH_DIR KEY_COMMENT KEY_TYPE KEY_BITS; do
        if [[ -z "${!var}" ]]; then
            echo "ERROR: Required variable '$var' is not set"
            echo "       Configuration file: '$ENV_FILE'"
            echo "       $CONFIG_EXAMPLES"
            exit 1
        fi
    done

    # Additional validation for specific variables
    if [[ ! "$KEY_BITS" =~ ^[0-9]+$ || "$KEY_BITS" -lt 1024 ]]; then
        echo "ERROR: KEY_BITS must be a number greater than or equal to 1024 - Found: '$KEY_BITS'"
        echo "       Configuration file: '$ENV_FILE'"
        echo "       Example:"
        echo "         KEY_BITS=4096"
        exit 1
    fi
    if [[ "$KEY_TYPE" != "rsa" && "$KEY_TYPE" != "ecdsa" && "$KEY_TYPE" != "ed25519" ]]; then
        echo "ERROR: KEY_TYPE must be 'rsa', 'ecdsa', or 'ed25519' - Found: '$KEY_TYPE'"
        echo "       Configuration file: '$ENV_FILE'"
        echo "       Example:"
        echo "         KEY_TYPE=rsa"
        exit 1
    fi
    if [[ ! -d "$(dirname "$SRC_DIR")" ]]; then
        echo "ERROR: Configured source directory does not exist: '$(dirname "$SRC_DIR")'"
        echo "       Configuration file: '$ENV_FILE'"
        echo "       Example:"
        echo "         SRC_DIR=/path/to/source_directory/.ssh"
        exit 1
    fi
    if [[ ! -d "$(dirname "$SSH_DIR")" ]]; then
        echo "ERROR: Configured SSH directory does not exist: '$(dirname "$SSH_DIR")'"
        echo "       Configuration file: '$ENV_FILE'"
        echo "       Example:"
        echo "         SSH_DIR=/path/to/ssh_directory/.ssh"
        exit 1
    fi
    # Validate SSH_DIR ends with .ssh before creation or use
    if [[ "$SSH_DIR" != *.ssh ]]; then
        echo "WARNING: SSH_DIR does not end with '.ssh' - Found: '$SSH_DIR'"
        echo "         This is not a standard SSH directory name"
        echo "         This is not recommended!"
        echo "         Configuration file: '$ENV_FILE'"
        echo "         Recommended:"
        echo "           SSH_DIR=/path/to/ssh_directory/.ssh"
        while true; do
            read -p "Would you like to continue anyway? [y/n]: " response
            response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
            case "$response_lower" in
                y|yes)
                    break
                    ;;
                n|no)
                    echo "Operation canceled"
                    exit 1
                    ;;
                *)
                    echo "Invalid input - Please enter yes or no (y/n)"
                    continue
                    ;;
            esac
        done
    fi
    # Create SSH_DIR if it doesn't exist, after validation
    if [[ ! -d "$SSH_DIR" ]]; then
        mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR" || {
            echo "ERROR: Failed to create SSH_DIR: '$SSH_DIR'"
            exit 1
        }
    fi
}

# Call the validation function immediately
validate_config

### Global State Tracking ###
declare -A copied_files original_permissions temp_files pub_fingerprints processed_dests
declare -a valid_private valid_public encrypted_private invalid_keys

### Cleanup and Error Handling ###
cleanup() {
    echo -e "\nCleaning temporary resources..."
    for temp_file in "${temp_files[@]}"; do rm -f "$temp_file"; done
    for key in "${!original_permissions[@]}"; do chmod "${original_permissions[$key]}" "$key"; done
    echo -e "\nDone"
}
trap cleanup EXIT ERR INT TERM

validate_ssh_key() {
    local key_file="$1" is_private=false temp_copy
    echo "Validating: '$key_file'"

    [[ -s "$key_file" ]] || { echo "  Invalid: Empty file ('$key_file')"; invalid_keys+=("$key_file"); return 1; }
    [[ "$key_file" != *.pub ]] && is_private=true

    if $is_private; then
        original_permissions["$key_file"]=$(stat -c "%a" "$key_file")
        temp_copy=$(mktemp)
        temp_files["$temp_copy"]=1
        cp "$key_file" "$temp_copy" && chmod 600 "$temp_copy"

        if ssh-keygen -y -P "" -f "$temp_copy" >/dev/null 2>&1; then
            # Key works with empty passphrase, but check if encrypted with "wrong"
            if ssh-keygen -y -P "keyisencrypted" -f "$temp_copy" >/dev/null 2>&1 && ! ssh-keygen -y -P "arewesurekeyisencrypted" -f "$temp_copy" >/dev/null 2>&1; then
                echo "  Valid encrypted private key (passphrase is 'keyisencrypted'): '$key_file'"
                encrypted_private+=("$key_file")
            else
                echo "  Valid private key: '$key_file'"
                valid_private+=("$key_file")
            fi
        elif ssh-keygen -y -P "keyisencrypted" -f "$temp_copy" 2>&1 | grep -q "incorrect passphrase"; then
            echo "  Valid encrypted private key: '$key_file'"
            encrypted_private+=("$key_file")
        else
            echo "  Invalid private key: '$key_file'"
            invalid_keys+=("$key_file")
        fi
    else
        if ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
            echo "  Valid public key: '$key_file'"
            valid_public+=("$key_file")
            fingerprint=$(ssh-keygen -l -f "$key_file" | awk '{print $2}')
            pub_fingerprints["$fingerprint"]="$key_file"
        else
            echo "  Invalid public key: '$key_file'"
            invalid_keys+=("$key_file")
        fi
    fi
}

### Enhanced Conflict Resolution ###
handle_existing_file() {
    local src="$1" dest="$2"
    local base="$(basename "$src")"

    echo -e "Checking existence of: '$dest'"

    if [ -f "$dest" ]; then
        echo "Conflict detected: '$base' already exists in '$SSH_DIR'"
        if [[ "$src" == *.pub ]]; then is_public=true; else is_public=false; fi
        trap 'echo -e "\nOperation canceled for \"$base\""; return 1' INT
        
        echo "Conflict resolution actions for '$base':"
        echo "  1. \"Overwrite\" existing file ('$dest')"
        echo "  2. \"Rename\" file to be copied: ('$src')"
        echo "  3. \"Cancel\" (or CTRL+C)"
        while true; do
            read -p "  Choose action for '$base': " choice
            choice_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
            case "$choice_lower" in
                "1"|"overwrite")
                    echo -e "Overwriting existing file..."
                    printf "  %s\n" "$(cp -fv "$src" "$dest")"
                    copied_files["$src"]="$dest"
                    trap - INT
                    return 0
                    ;;
                "2"|"rename")
                    while true; do
                        read -p "  Enter new filename (CTRL+C to cancel): " new_name
                        if [[ -z "$new_name" ]]; then
                            echo "ERROR: Filename cannot be empty"
                            continue
                        fi
                        new_name="${new_name##*/}"
                        if [[ "$new_name" == */* ]]; then
                            echo "ERROR: Filename cannot contain forward-slashes"
                            continue
                        fi
                        if (( ${#new_name} > 255 )); then
                            echo "ERROR: Exceeded character limit (max 255 bytes)"
                            continue
                        fi
                        if [[ ! "$new_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
                            echo "ERROR: Disallowed characters in filename"
                            echo "       Allowed characters: letters, numbers, dots, underscores, hyphens"
                            continue
                        fi
                        if $is_public; then
                            if [[ "$new_name" != *.pub ]]; then
                                echo "ERROR: Requires '.pub' extension for public key"
                                continue
                            fi
                        else
                            if [[ "$new_name" == *.pub ]]; then
                                echo "ERROR: Not a public key - Filename must not end with '.pub'"
                                continue
                            fi
                        fi
                        new_dest="$SSH_DIR/$new_name"
                        if [ -e "$new_dest" ]; then
                            echo "ERROR: Filename already exists in '$SSH_DIR'"
                            continue
                        fi
                        echo -e "Copying with new name..."
                        printf "  %s\n" "$(cp -v "$src" "$new_dest")"
                        copied_files["$src"]="$new_dest"
                        trap - INT
                        return 0
                    done
                    ;;
                "3"|"cancel")
                    echo "Operation canceled for '$base'"
                    trap - INT
                    return 1
                    ;;
                *)
                    echo "Invalid choice - Please choose option 1, 2, or 3"
                    continue
                    ;;
            esac
        done
        trap - INT
    else
        echo -e "No conflict detected - Copying..."
        printf "  %s\n" "$(cp -v "$src" "$dest")"
        copied_files["$src"]="$dest"
        return 0
    fi
}

### Key Pair Validation ###
validate_key_pairs() {
    local -a valid_private_tmp valid_public_tmp
    local has_errors=false

    for priv in "${valid_private[@]}" "${encrypted_private[@]}"; do
        local base_name="${priv##*/}"
        local expected_pub="${priv}.pub"
        local is_encrypted=false

        if [[ " ${encrypted_private[@]} " =~ " $priv " ]]; then
            is_encrypted=true
        fi

        if $is_encrypted; then
            if [[ -f "$expected_pub" && " ${valid_public[@]} " =~ " $expected_pub " ]]; then
                valid_private_tmp+=("$priv")
                valid_public_tmp+=("$expected_pub")
            else
                echo "ERROR: Missing public key for encrypted private key: '$base_name'"
                echo "       Possible filename mismatch"
                echo "       Expected: ${expected_pub##*/}"
                has_errors=true
                invalid_keys+=("$priv")
            fi
        else
            echo "WARNING: Private key '$base_name' has no passphrase (unencrypted)"
            echo "         This is not recommended for security!"
            echo "         To add a passphrase manually, use:"
            echo "           ssh-keygen -p -f '$priv'"

            temp_copy=$(mktemp)
            temp_files["$temp_copy"]=1
            cp "$priv" "$temp_copy" && chmod 600 "$temp_copy"

            pub_content=$(ssh-keygen -y -P "" -f "$temp_copy" 2>/dev/null)
            if [[ -z "$pub_content" ]]; then
                echo "ERROR: Unable to generate public key from private key: '$base_name'"
                has_errors=true
                invalid_keys+=("$priv")
                continue
            fi

            fingerprint=$(echo "$pub_content" | ssh-keygen -l -f /dev/stdin 2>/dev/null | awk '{print $2}')
            if [[ -z "$fingerprint" ]]; then
                echo "ERROR: Unable to compute fingerprint for private key: '$base_name'"
                has_errors=true
                invalid_keys+=("$priv")
                continue
            fi

            local matching_pub="${pub_fingerprints[$fingerprint]}"
            if [[ -n "$matching_pub" ]]; then
                if [[ "$matching_pub" != "$expected_pub" ]]; then
                    echo "ERROR: Key pair filename mismatch:"
                    echo "       Private: $base_name"
                    echo "       Public: ${matching_pub##*/}"
                    echo "       Expected: ${expected_pub##*/}"
                    has_errors=true
                    invalid_keys+=("$priv" "$matching_pub")
                else
                    valid_private_tmp+=("$priv")
                    valid_public_tmp+=("$matching_pub")
                fi
            else
                if [[ -f "$expected_pub" ]]; then
                    echo "ERROR: Fingerprint mismatch for key pair: '$base_name'"
                    has_errors=true
                    invalid_keys+=("$priv" "$expected_pub")
                fi
            fi
        fi
    done

    if $has_errors; then
        echo "Aborting due to validation errors..."
        exit 1
    fi

    valid_private=("${valid_private_tmp[@]}")
    valid_public=("${valid_public_tmp[@]}")
}

### Key Generation ###
generate_key_pair() {
    local key_path="$SRC_DIR/${1:-id_rsa}"

    echo -e "Generating new key pair:\n  '$key_path'\n  '$key_path.pub'"
    echo "  >ssh-keygen -t $KEY_TYPE -b $KEY_BITS -C $KEY_COMMENT -f $key_path" # Show the user what command the script is running
    echo "  **If you provide an empty passphrase, the private key is saved in plaintext (unencrypted)"
    echo "  **Entering an empty passphrase is not recommended!"
    echo "  **Don't forget your passphrase! A forgotten passphrase cannot be recovered" 
    ssh-keygen -t "$KEY_TYPE" -b "$KEY_BITS" -C "$KEY_COMMENT" -f "$key_path"
    if [ $? -eq 0 ]; then
        encrypted_private+=("$key_path")
        valid_public+=("$key_path.pub")
    else
        echo "ERROR: Key generation failed"
        exit 1
    fi
}

### Permission Management ###
set_key_permissions() {
    declare -A unique_private_keys
    for key in "${valid_private[@]}" "${encrypted_private[@]}"; do
        unique_private_keys["$key"]=1
    done

    for key in "${!unique_private_keys[@]}"; do
        dest="${copied_files[$key]}"
        if [[ -n "$dest" && -f "$dest" ]]; then
            chmod 600 "$dest"
            echo "Set permissions 600 for: $(basename "$dest")"
        fi
    done

    for key in "${valid_public[@]}"; do
        dest="${copied_files[$key]}"
        if [[ -n "$dest" && -f "$dest" ]]; then
            chmod 644 "$dest"
            echo "Set permissions 644 for: $(basename "$dest")"
        fi
    done
}

### Agent Management ###
manage_ssh_agent() {
    ssh_agent_running() {
        if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
            if ssh-add -l >/dev/null 2>&1 || [ $? -eq 1 ]; then
                return 0
            fi
        fi
        return 1
    }

    echo -e "\n=== SSH Agent Status Check ==="
    echo "Current SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
    echo "Current SSH_AGENT_PID: ${SSH_AGENT_PID:-not set}"

    if ssh_agent_running; then
        echo -e "SSH-Agent is running and accessible (PID: ${SSH_AGENT_PID:-unknown})\n"
        echo "Currently loaded keys in agent:"
        ssh-add -l | while IFS= read -r line; do
            [[ -n "$line" ]] && printf "  %s\n" "$line" || echo "  No keys currently loaded"
        done
    else
        echo "ERROR: SSH Agent is not running or not accessible"
        echo "       To start an SSH Agent manually, run the following command in your terminal:"
        echo "         eval \"\$(ssh-agent -s)\""
        echo "       Then re-run this script"
        echo "Current environment:"
        echo "  SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
        echo "  SSH_AGENT_PID: ${SSH_AGENT_PID:-not set}"
        if [ -n "${SSH_AUTH_SOCK:-}" ]; then
            echo "Note: SSH_AUTH_SOCK is set but agent is not responding"
            echo "      You may need to kill existing agents with: pkill ssh-agent"
        fi
        exit 1
    fi

    for src in "${!copied_files[@]}"; do
        [[ "$src" == *".pub" ]] && continue
        key_path="${copied_files[$src]}"
        echo "Attempting to add key identity to SSH-Agent: '$(basename "$key_path")'"
        
        if [[ " ${encrypted_private[@]} " =~ " $src " ]]; then
            if [[ -t 0 ]]; then
                echo "Adding encrypted private key identity to SSH-Agent: '$(basename "$key_path")'"
                echo "  >ssh-add $key_path" # Show the user what command the script is running
                echo "Passphrase required..."
                ssh-add "$key_path" </dev/tty || { 
                    echo "ERROR: Failed to add encrypted key identity to SSH-Agent: '$(basename "$key_path")'"
                    echo "       Check passphrase and permissions"
                    echo "       Expected: Permissions 0600"
                    echo "       Current Permissions: 0$(stat -c "%a" "$key_path")"
                    echo "                            $(ls -l "$key_path")"
                    echo "       SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
                    exit 1
                }
                echo "Successfully added encrypted key identity to SSH-Agent"
            else
                echo "ERROR: Cannot add encrypted key identity '$(basename "$key_path")' in non-interactive mode"
                echo "       Passphrase required for encrypted key"
                exit 1
            fi
        else
            ssh-add "$key_path" 2>/dev/null || { 
                echo "ERROR: Failed to add unencrypted key identity to SSH-Agent: '$(basename "$key_path")'"
                echo "       Check passphrase and permissions"
                echo "       Expected: Permissions 0600"
                echo "       Current Permissions: 0$(stat -c "%a" "$key_path")"
                echo "                            $(ls -l "$key_path")"
                echo "       SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
                exit 1
            }
            echo "Successfully added unencrypted key identity to SSH-Agent"
        fi
    done

    echo -e "\n=== Final SSH-Agent Status ==="
    echo "SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-not set}"
    echo "SSH_AGENT_PID: ${SSH_AGENT_PID:-not set}"
    echo "Loaded SSH Keys:"
    ssh-add -l | while IFS= read -r line; do
        [[ -n "$line" ]] && printf "  %s\n" "$line" || echo "  No keys loaded in agent"
    done
}

### Main Workflow ###
main() {
    echo "=== SSH Key Management ==="
    echo -e "Configuration file: '$ENV_FILE'\n  (where environment variables are set)"
    echo -e "SSH Key source directory set to: '$SRC_DIR'\n  (where SSH keys will be copied from or generated in)"
    echo -e "SSH Key destination directory set to: '$SSH_DIR'\n  (where SSH keys will be copied to)\n"

    echo "Please choose an option:"
    echo "  1. \"Copy\" existing SSH keys from '$SRC_DIR'"
    echo "  2. \"Generate\" new SSH keys"
    echo "  3. \"Cancel\" (or CTRL+C)"
    
    trap 'echo -e "\nOperation canceled"; exit 0' INT
    while true; do
        read -p "  Enter your choice (1, 2, or 3): " initial_choice
        if [[ -z "$initial_choice" ]]; then
            echo "  Invalid choice - Please enter 1, 2, or 3 (CTRL+C to cancel)"
            continue
        fi
        initial_choice_lower=$(echo "$initial_choice" | tr '[:upper:]' '[:lower:]')
        case "$initial_choice_lower" in
            "1"|"copy"|"2"|"generate"|"3"|"cancel")
                break
                ;;
            *)
                echo "  Invalid choice - Please enter 1, 2, or 3 (CTRL+C to cancel)"
                continue
                ;;
        esac
    done
    trap cleanup EXIT ERR INT TERM

    initial_choice_lower=$(echo "$initial_choice" | tr '[:upper:]' '[:lower:]')
    case "$initial_choice_lower" in
        "1"|"copy")
            while IFS= read -r -d '' file; do
                validate_ssh_key "$file"
            done < <(find "$SRC_DIR" -type f -print0)

            if (( ${#invalid_keys[@]} > 0 )); then
                echo "ERROR: Invalid keys detected:"
                printf '  %s\n' "${invalid_keys[@]}"
                trap 'echo -e "\nOperation canceled"; exit 1' INT
                while true; do
                    read -p "Generate new SSH keys (key pair)? [y/n] (CTRL+C to cancel): " response
                    response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
                    case "$response_lower" in
                        y|yes)
                            trap 'echo -e "\nOperation canceled"; exit 1' INT
                            read -p "Enter new private key name (default: id_rsa) (CTRL+C to cancel): " key_name
                            generate_key_pair "${key_name:-id_rsa}"
                            break
                            ;;
                        n|no)
                            echo "Operation canceled"
                            exit 1
                            ;;
                        *)
                            echo "Invalid input - Please enter yes or no (y/n)"
                            continue
                            ;;
                    esac
                done
                trap - INT
            fi
            ;;
        "2"|"generate")
            trap 'echo -e "\nOperation canceled"; exit 1' INT
            while true; do
                read -p "Enter new private key name (default: id_rsa) (CTRL+C to cancel): " key_name
                key_name="${key_name:-id_rsa}"

                if [[ "$key_name" == */* ]]; then
                    echo "ERROR: Filename cannot contain forward-slashes"
                    continue
                fi
                if (( ${#key_name} > 255 )); then
                    echo "ERROR: Exceeded character limit (max 255 bytes)"
                    continue
                fi
                if [[ ! "$key_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
                    echo "ERROR: Disallowed characters in filename"
                    echo "       Allowed characters: letters, numbers, dots, underscores, hyphens"
                    continue
                fi
                if [[ "$key_name" == *.pub ]]; then
                    echo "ERROR: Not a public key - Filename must not end with '.pub'"
                    continue
                fi
                key_path="$SRC_DIR/$key_name"
                if [ -e "$key_path" ]; then
                    echo "ERROR: Filename already exists in '$SRC_DIR'"
                    continue
                fi
                break
            done
            trap - INT
            generate_key_pair "$key_name"
            ;;
        "3"|"cancel")
            echo "Operation canceled"
            exit 0
            ;;
        *)
            echo "Invalid choice - Please enter 1, 2, or 3"
            exit 1
            ;;
    esac

    validate_key_pairs
    local total_valid=$(( ${#valid_private[@]} + ${#encrypted_private[@]} ))

    if (( total_valid == 0 )); then
        echo "ERROR: No valid key pairs found"
        trap 'echo -e "\nOperation canceled"; exit 1' INT
        while true; do
            read -p "Generate new SSH keys (key pair)? [y/n] (CTRL+C to cancel): " response
            response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
            case "$response_lower" in
                y|yes)
                    trap 'echo -e "\nOperation canceled"; exit 1' INT
                    read -p "Enter new private key name (default: id_rsa) (CTRL+C to cancel): " key_name
                    generate_key_pair "${key_name:-id_rsa}"
                    break
                    ;;
                n|no)
                    echo "Operation canceled"
                    exit 1
                    ;;
                *)
                    echo "Invalid input - Please enter yes or no (y/n)"
                    continue
                    ;;
            esac
        done
        trap - INT
    fi

    for key in "${valid_private[@]}" "${encrypted_private[@]}" "${valid_public[@]}"; do
        [[ -z "$key" ]] && continue
        local dest="$SSH_DIR/$(basename "$key")"

        if [[ -n "${processed_dests[$dest]}" ]]; then
            continue
        fi
        
        handle_existing_file "$key" "$dest" || exit 1
        processed_dests["$dest"]=1
    done

    set_key_permissions
    manage_ssh_agent

    echo -e "\n=== Summary ==="
    printf "Copied SSH Keys:\n"
    for src in "${!copied_files[@]}"; do printf "  '%s' ➔ '%s'\n" "$src" "${copied_files[$src]}"; done
    echo "SSH-Agent Identities:"
    ssh-add -l | while IFS= read -r line; do
        [[ -n "$line" ]] && printf "  %s\n" "$line" || echo "  No keys loaded in agent"
    done
}

# Call main function only if validation passes
main

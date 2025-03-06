# SSH Key Management Script

## Purpose
The `SSH Key Management Script` (`ssh_key_management.sh`) is a Bash utility designed to streamline the process of managing SSH key pairs. It provides a robust solution for validating, copying, and generating SSH keys, ensuring strict permission enforcement and secure handling of files.

## What It Does
This script performs the following key functions:
- **Validates SSH Keys:** Checks the integrity of existing private and public SSH keys in a source directory.
- **Copies SSH Keys:** Transfers validated keys from a source directory (`SRC_DIR`) to a destination directory (`SSH_DIR`), with options to overwrite or rename files in case of conflicts.
- **Generates New SSH Keys:** Creates new RSA, ECDSA, or Ed25519 key pairs with user-specified names and adds them to the SSH Agent.
- **Manages SSH Agent:** Ensures the SSH Agent is running and adds the keys to it for immediate use.
- **Enforces Security:** Sets appropriate permissions (600 for private keys, 644 for public keys) and warns about unencrypted keys.

## Requirements
To work properly, the script requires:
- **Bash Shell:** Compatible with Bash 4.0 or later.
- **SSH Tools:** `ssh-keygen` and `ssh-add` must be installed as part of OpenSSH.
  - **Check if Installed:** Run `ssh-keygen --version` (or `-V` on some systems). If you see a version (e.g., `OpenSSH_8.9p1`), it’s installed. If `command not found`, install it:
  - **Install OpenSSH:**
    - **Ubuntu/Debian:** `sudo apt update && sudo apt install openssh-client`
    - **Fedora/RHEL:** `sudo dnf install openssh-clients` (or `yum` for older versions)
    - **macOS:** Comes pre-installed; update via `brew install openssh` (requires [Homebrew](https://brew.sh/))
    - **Windows (WSL):** Use Ubuntu/Debian instructions in WSL terminal
    - **Windows (Native):** Enable via `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` in PowerShell, or download from [OpenSSH GitHub](https://github.com/PowerShell/Win32-OpenSSH/releases)
- **SSH Agent:** An active SSH Agent must be running (start with `eval "$(ssh-agent -s)"` if needed).
- **Configuration File:** A file named `ssh_manager_config.env` in the same directory as the script, containing required environment variables: `SRC_DIR`, `SSH_DIR`, `KEY_COMMENT`, `KEY_TYPE`, `KEY_BITS`.
- **File System Permissions:** Write access to `SRC_DIR` and `SSH_DIR` (or their parent directories if they need to be created).

## Configuration Variables
The script reads its configuration from `ssh_manager_config.env` (which should be located in the same directory as the `ssh_key_management.sh` script file). All variables are mandatory, with no defaults. Below are the required variables:

    SRC_DIR:     Source directory for SSH keys (to copy from or generate into)
                 Example: /path/to/source_directory/.ssh

    SSH_DIR:     Destination directory for SSH keys (must end with .ssh unless confirmed)
                 Example: /path/to/ssh_directory/.ssh

    KEY_COMMENT: Comment for generated SSH keys (e.g., an email)
                 Example: user@example.com

    KEY_TYPE:    Type of SSH key to generate (rsa, ecdsa, or ed25519)
                 Example: rsa

    KEY_BITS:    Key size in bits (minimum 1024)
                 Example: 4096

### Example `ssh_manager_config.env`
```bash
SRC_DIR=/media/user/source/.ssh
SSH_DIR=/home/user/.ssh
KEY_COMMENT=user@example.com
KEY_TYPE=rsa
KEY_BITS=4096
```

## How to Use
1. **Prepare the Configuration:**
   - Configuration file should already be included in `sshkey-manager` folder, but if it's not for some reason:
     - Create `ssh_manager_config.env` in the same directory as the script.
     - Populate it with the required variables (see above).

2. **Ensure SSH Agent is Running:**
   - Run `eval "$(ssh-agent -s)"` in your terminal if no agent is active.

3. **Make the Script Executable:**
   ```bash
   chmod +x ssh_key_management.sh
   ```

4. **Run the Script:**
   ```bash
   ./ssh_key_management.sh
   ```

5. **Follow Prompts:**
   - Choose an option (1, 2, or 3) when prompted.
   - Respond to any conflict resolution or additional prompts as needed.

## Possible Outputs and Inputs

### Successful/Expected Outputs

#### Initial Prompt
```
=== SSH Key Management ===
Configuration file: '/path/to/ssh_key_management.sh/ssh_manager_config.env'
  (where environment variables are set)
SSH Key source directory set to: '/media/user/source/.ssh'
  (where SSH keys will be copied from or generated in)
SSH Key destination directory set to: '/home/user/.ssh'
  (where SSH keys will be copied to)

Please choose an option:
  1. "Copy" existing SSH keys from '/media/user/source/.ssh'
  2. "Generate" new SSH keys
  3. "Cancel" (or CTRL+C)
  Enter your choice (1, 2, or 3):
```
- **Input:** `1` or `copy`, `2` or `generate`, `3` or `cancel` (case-insensitive). Pressing `CTRL+C` will also cancel.
- **Empty Input:** Re-prompts with `Invalid choice - Please enter 1, 2, or 3 (CTRL+C to cancel)`.

#### Option 1: Copy Existing Keys (Successful)
```
  Enter your choice (1, 2, or 3): 1
Validating: '/media/user/source/.ssh/id_rsa'
  Valid private key: '/media/user/source/.ssh/id_rsa'
Validating: '/media/user/source/.ssh/id_rsa.pub'
  Valid public key: '/media/user/source/.ssh/id_rsa.pub'
Checking existence of: '/home/user/.ssh/id_rsa'
  No conflict detected - Copying...
  '/media/user/source/.ssh/id_rsa' -> '/home/user/.ssh/id_rsa'
Checking existence of: '/home/user/.ssh/id_rsa.pub'
  No conflict detected - Copying...
  '/media/user/source/.ssh/id_rsa.pub' -> '/home/user/.ssh/id_rsa.pub'
Set permissions 600 for: id_rsa
Set permissions 644 for: id_rsa.pub
[SSH Agent Output...]
=== Summary ===
Copied SSH Keys:
  '/media/user/source/.ssh/id_rsa' ➔ '/home/user/.ssh/id_rsa'
  '/media/user/source/.ssh/id_rsa.pub' ➔ '/home/user/.ssh/id_rsa.pub'
SSH-Agent Identities:
  [displays key fingerprint(s) or "No keys loaded in agent"]
```

#### Option 2: Generate New Keys (Successful)
```
  Enter your choice (1, 2, or 3): 2
Enter new private key name (default: id_rsa) (CTRL+C to cancel): mykey
Generating new key pair:
  '/media/user/source/.ssh/mykey'
  '/media/user/source/.ssh/mykey.pub'
  >ssh-keygen -t rsa -b 4096 -C user@example.com -f /media/user/source/.ssh/mykey
  **If you provide an empty passphrase, the private key is saved in plaintext (unencrypted)
  **Entering an empty passphrase is not recommended!
  **Don't forget your passphrase! A forgotten passphrase cannot be recovered
Enter passphrase (empty for no passphrase): [user enters passphrase]
[SSH Agent Output...]
=== Summary ===
Copied SSH Keys:
  '/media/user/source/.ssh/mykey' ➔ '/home/user/.ssh/mykey'
  '/media/user/source/.ssh/mykey.pub' ➔ '/home/user/.ssh/mykey.pub'
SSH-Agent Identities:
  [displays key fingerprint(s)]
```

#### Option 3: Cancel
```
  Enter your choice (1, 2, or 3): 3
Operation canceled

Cleaning temporary resources...

Done
```

### Error/Warning Outputs:

#### Missing Config File
```
ERROR: Configuration file (ssh_manager_config.env) not found
       Expected: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Please create it with the required variables
       Examples:
         SRC_DIR=/path/to/source_directory/.ssh
         SSH_DIR=/path/to/ssh_directory/.ssh
         KEY_COMMENT=email@domain.com
         KEY_TYPE=rsa
         KEY_BITS=4096
```

#### Missing Variable
```
ERROR: Required variable 'KEY_COMMENT' is not set
       Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Examples:
         SRC_DIR=/path/to/source_directory/.ssh
         SSH_DIR=/path/to/ssh_directory/.ssh
         KEY_COMMENT=email@domain.com
         KEY_TYPE=rsa
         KEY_BITS=4096
```

#### Invalid `KEY_BITS`
```
ERROR: KEY_BITS must be a number greater than or equal to 1024 - Found: '512'
       Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Example:
         KEY_BITS=4096
```

#### Invalid `KEY_TYPE`
```
ERROR: KEY_TYPE must be 'rsa', 'ecdsa', or 'ed25519' - Found: 'xyz'
       Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Example:
         KEY_TYPE=rsa
```

#### Non-existent Source Directory
```
ERROR: Configured source directory does not exist: '/nonexistent/path'
       Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Example:
         SRC_DIR=/path/to/source_directory/.ssh
```

#### Non-existent SSH Directory
```
ERROR: Configured SSH directory does not exist: '/nonexistent/path'
       Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
       Example:
         SSH_DIR=/path/to/ssh_directory/.ssh
```

#### Non-standard `SSH_DIR` (e.g., `/home/user/.mykeys`)
```
WARNING: SSH_DIR does not end with '.ssh' - Found: '/home/user/.mykeys'
         This is not a standard SSH directory name
         This is not recommended!
         Configuration file: '/path/to/ssh_key_management_script/ssh_manager_config.env'
         Recommended:
           SSH_DIR=/path/to/ssh_directory/.ssh
Would you like to continue anyway? [y/n]:
```
- **Input `y` or `yes`:** Proceeds with `/home/user/.mykeys`.
- **Input `n` or `no`:** `Operation canceled`.
- **Invalid Input:** `Invalid input - Please enter yes or no (y/n)` (re-prompts).

#### Failed SSH Directory Creation
```
ERROR: Failed to create SSH_DIR: '/home/user/.ssh'
```

#### Invalid Choice (Re-prompt)
```
  Enter your choice (1, 2, or 3): 4
  Invalid choice - Please enter 1, 2, or 3
  Enter your choice (1, 2, or 3):
```

#### Empty Choice (Re-prompt)
```
  Enter your choice (1, 2, or 3): 
  Invalid choice - Please enter 1, 2, or 3 (CTRL+C to cancel)
  Enter your choice (1, 2, or 3):
```

#### Pressing [CTRL+C]
```
^C
Operation canceled

Cleaning temporary resources...

Done
```

#### Invalid Key (Re-prompt)
```
Validating: '/media/user/source/.ssh/id_rsa'
  Invalid private key: '/media/user/source/.ssh/id_rsa'
ERROR: Invalid keys detected:
  '/media/user/source/.ssh/id_rsa'
Generate new SSH keys (key pair)? [y/n] (CTRL+C to cancel):
```

- **Validation Logic** in `validate_ssh_key`

  The `validate_ssh_key()` function checks each file in the `SRC_DIR` directory and categorizes it as a private or public key, determining its validity and encryption status.

  **Private Key Checks**
    
    The `validate_ssh_key()` function uses `[[ "$key_file" != *.pub ]]` to identify potential private key files, then performs the following checks:
  - **Empty File:** If the file is empty (`[[ ! -s "$key_file" ]]`), it’s invalid (`Invalid: Empty file`).
  - **Validity and Encryption Status:** The script uses a three-step process with `ssh-keygen` to classify the private key:

      - **1.) Unencrypted Key Test:** The function runs `ssh-keygen -y -P "" -f "$temp_copy"` to test if the file is a valid unencrypted private key (no passphrase). If this succeeds:

      - **2.) Edge Case Check:** The function runs `ssh-keygen -y -P "keyisencrypted"` and `ssh-keygen -y -P "arewesurekeyisencrypted"`. If using the "`keyisencrypted`" passphrase succeeds but the "`arewesurekeyisencrypted`" passphrase fails, the private key is determined to be encrypted with the passphrase "`keyisencrypted`" (`Valid encrypted private key with the passphrase "keyisencrypted"`). Otherwise, it’s determined to be an unencrypted private key (`Valid private key`). 

        This second check addresses the rare, but possible, scenario where a private key is encrypted with an empty passphrase (i.e., ""). This edge case creates ambiguity because an encrypted key with an empty passphrase behaves identically to an unencrypted key in the initial test: both will pass `ssh-keygen -y -P ""`. Without the additional checks, the script would misclassify such an encrypted key as unencrypted, leading to potential issues later (e.g., in `manage_ssh_agent`).

      - **3.) Encrypted Key Test:** If the empty passphrase test fails, the function runs `ssh-keygen -y -P "keyisencrypted"`. If this fails with an "incorrect passphrase" error (checked via `grep -q "incorrect passphrase"`), the private key is determined to be encrypted with a different passphrase (`Valid encrypted private key`).

  - **Invalid Key:** If each test fails without an "incorrect passphrase" error (e.g., due to corruption or invalid format), the private key is determined to be invalid (`Invalid private key`).
  
  **Public Key Checks**
  
  The `validate_ssh_key()` function uses `[[ "$key_file" == *.pub ]]` to check if a file is a possible public key file.

  - **Empty File:** If the file is empty (`[[ ! -s "$key_file" ]]`), it's determined to be invalid (`Invalid: Empty file`).
  - **Not a Valid Public Key:** The script uses `ssh-keygen -l -f "$key_file"` to verify if it’s a valid public key. If this fails, the public key is determined to be invalid (`Invalid public key`).

#### Existing File Conflict (e.g., `id_rsa` already in `SSH_DIR`)
```
Checking existence of: '/home/user/.ssh/id_rsa'
Conflict detected: 'id_rsa' already exists in '/home/user/.ssh'
Conflict resolution actions for 'id_rsa':
  1. "Overwrite" existing file ('/home/user/.ssh/id_rsa')
  2. "Rename" file to be copied: ('/media/user/source/.ssh/id_rsa')
  3. "Cancel" (or CTRL+C)
  Choose action for 'id_rsa':
```
- **Input `1` or `overwrite`:** Overwrites the existing key file in the `SSH_DIR` directory with the key file being copied from the `SRC_DIR` directory.
- **Input `2` or `rename`:** Prompts for new filename to rename the key file in the `SRC_DIR` directory before copying it to the `SSH_DIR` directory.
- **Input `3` or `cancel`:** Cancels operation for that file. Pressing `CTRL+C` will also cancel.


#### File Conflict - Empty Key Name (Re-prompt)
```
Checking existence of: '/home/user/.ssh/id_rsa'
Conflict detected: 'id_rsa' already exists in '/home/user/.ssh'
Conflict resolution actions for 'id_rsa':
  1. "Overwrite" existing file ('/home/user/.ssh/id_rsa')
  2. "Rename" file to be copied: ('/media/user/source/.ssh/id_rsa')
  3. "Cancel" (or CTRL+C)
  Choose action for 'id_rsa': 2
  Enter new filename (CTRL+C to cancel): 
ERROR: Filename cannot be empty
  Enter new filename (CTRL+C to cancel):
```
- Re-prompts until a non-empty name is provided.

#### Key Name with Forward Slashes (Re-Prompt)
```
  Enter new filename (default: id_rsa) (CTRL+C to cancel): my/key
ERROR: Filename cannot contain forward-slashes
  Enter new filename (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a name without `/` is provided.

#### Key Name Exceeds Character Limit (255 bytes) (Re-prompt)
```
  Enter new filename (default: id_rsa) (CTRL+C to cancel): ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
ERROR: Exceeded character limit (max 255 bytes)
  Enter new filename (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a name ≤ 255 bytes is provided.

#### Key Name with Disallowed Characters (Re-prompt)
```
  Enter new filename (default: id_rsa) (CTRL+C to cancel): my@key!
ERROR: Disallowed characters in filename
       Allowed characters: letters, numbers, dots, underscores, hyphens
  Enter new filename (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a name with only `[A-Za-z0-9._-]` is provided.

#### Private Key Name Ending with `.pub` (Re-prompt)
```
  Enter new private key name (default: id_rsa) (CTRL+C to cancel): mykey.pub
ERROR: Not a public key - Filename must not end with '.pub'
  Enter new private key name (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a private key name not ending in `.pub` is provided (only thrown for private key filenames).

#### Public Key Name Not Ending with `.pub` (Re-prompt)
```
  Enter new filename (default: id_rsa) (CTRL+C to cancel): mykey
ERROR: Requires '.pub' extension for public key
  Enter new filename (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a public key name ending in `.pub` is provided (only thrown for public key filenames).

#### Key Name Already Exists (Re-prompt)
```
  Enter new private key name (default: id_rsa) (CTRL+C to cancel): id_rsa
ERROR: Filename already exists in '/media/user/source/.ssh'.
  Enter new private key name (default: id_rsa) (CTRL+C to cancel):
```
- Re-prompts until a unique name is provided (checks existing filenames in `SRC_DIR`).

#### Key Generation Failure (e.g., insufficient permissions or disk space)
```
Enter new private key name (default: id_rsa) (CTRL+C to cancel): mykey
Generating new key pair:
  '/media/user/source/.ssh/mykey'
  '/media/user/source/.ssh/mykey.pub'
  >ssh-keygen -t rsa -b 4096 -C user@example.com -f /media/user/source/.ssh/mykey
  **If you provide an empty passphrase, the private key is saved in plaintext (unencrypted)
  **Entering an empty passphrase is not recommended!
  **Don't forget your passphrase! A forgotten passphrase cannot be recovered
ERROR: Key generation failed
```
- Thrown if `ssh-keygen` fails (e.g., due to no write permission).

#### SSH Agent Not Running
```
ERROR: SSH Agent is not running or not accessible
       To start an SSH Agent manually, run the following command in your terminal:
         eval "$(ssh-agent -s)"
       Then re-run this script
Current environment:
  SSH_AUTH_SOCK: not set
  SSH_AGENT_PID: not set
```
- #### SSH Agent Status Check 
  The script includes a helper function, `ssh_agent_running()`, to verify that an SSH Agent is active and operational before attempting to add keys. This function checks:

    - ##### Agent Environment: 
      It confirms that the `SSH_AUTH_SOCK` environment variable is set (indicating an agent is running) and points to a valid socket file (a special file used for communication with the agent).
    - ##### Agent Responsiveness: 
      It tests if the agent can list loaded keys using `ssh-add -l`. If this command succeeds (no keys or some keys listed) or fails with a specific "no identities" error, the agent is considered running. If the socket is invalid or the agent doesn’t respond, it’s deemed not running.
    - ##### Outcome: 
      Returns `0` (success) if the agent is running and responsive, or `1` (failure) if the agent is not running, allowing the script to proceed or exit with an error message accordingly.

---
## Author Details
- **Name:** James Logan Forsyth
- **Email:** james3895@duck.com
- **Date Created:** March 2025
- **License:** MIT License

      Copyright (c) 2025 - James Logan Forsyth
      
      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
      THE SOFTWARE.

---

# MobaXterm Fix

This document describes the fix implemented for the CloudyPad CLI when running in MobaXterm environments.

## Issue

MobaXterm has a different file system permission model than standard Linux environments. When running the CloudyPad CLI in MobaXterm, there were permission issues when trying to access or write to the `$HOME/.cloudypad` directory, resulting in errors like:

```
Error: Couldn't write config... Error: EACCES: permission denied, open '/home/mobaxterm/.cloudypad/config.yml'
```

## Solution

The solution involves:

1. Detecting MobaXterm environment (`$HOME` starts with `/home/mobaxterm`)
2. Using an alternative configuration directory inside the container at `/tmp/cloudypad_config`
3. Setting an environment variable `CLOUDYPAD_CONFIG_DIR` to tell the application where to find/store its configuration
4. Ensuring the temporary directory has proper permissions (777) before executing the application

## Technical Implementation

1. In `cloudypad.sh`, we detect MobaXterm environment and set a special flag
2. Instead of mounting the problematic `$HOME/.cloudypad` directory, we use an in-container directory
3. We modified the TypeScript code to respect the `CLOUDYPAD_CONFIG_DIR` environment variable
4. When running the container, we first create the temporary directory with proper permissions

This approach completely bypasses the problematic file system areas in MobaXterm while maintaining all functionality.

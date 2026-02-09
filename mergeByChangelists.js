const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m"
};

// Save original functions
const originalWarn = console.warn;
const originalError = console.error;
const originalLog = console.log;

console.warn = (...args) => {
    originalWarn(colors.yellow + "[WARNING]", ...args, colors.reset);
};

console.error = (...args) => {
    originalError(colors.red + "[ERROR]", ...args, colors.reset);
};

console.log = (...args) => {
    originalLog(colors.cyan, ...args, colors.reset);
};

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ================= CONFIGURATION =================
const CHANGE_LIST_FILE = path.resolve(__dirname, 'changelists.txt');

// Source Workspaces
const SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Company_Windows' 
    : '/Users/hoangnguyen/Perforce/Company_MacbookPro'; 
const COMBAT_LUA_SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Company_Windows_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/Company_MacbookPro_Combat_Lua';

// Target Workspaces
const CLIENT_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client' 
    : '/Users/hoangnguyen/Perforce/Desktop_Merge_Target_Client'; 
const COMBAT_LUA_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/Desktop_Merge_Target_Combat_Lua';

const NEW_CL_DESCRIPTION = 'Auto merge files from Source to Target based on CLs';

// ================= HELPER FUNCTIONS =================

function syncSourceToLatest(workspace) {
    console.log(`--- Syncing Workspace (${workspace}) to the latest revision... ---`);
    const cmd = `p4 sync //...`; 
    const output = runP4Command(cmd, workspace); 
    if (output != null) {
        const syncMessage = output.split('\n').find(line => line.includes('...')) || 'Sync completed successfully.';
        console.log(`[P4 SYNC OK] ${syncMessage}`);
        return true;
    }
    console.error(`[ERROR] Failed to sync workspace: ${workspace}`);
    return false;
}

function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 100 
        });
        return output.trim();
    } catch (error) {
        console.error(`[ERROR] Failed to run command: ${command} at ${cwd}`);
        console.error(error.message);
        return null;
    }
}

function getChangelistNumbers(filePath) {
    if (!fs.existsSync(filePath)) {
        console.error(`[ERROR] File not found: ${filePath}`);
        return [];
    }
    const content = fs.readFileSync(filePath, 'utf8');
    const cls = content.split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0 && !isNaN(line));
    const uniqueCls = [...new Set(cls)];
    return uniqueCls.sort((a, b) => Number(a) - Number(b));
}

function getChangedFilesFromCLs(clArray) {
    const fileActions = new Map(); 
    console.log(`--- Scanning ${clArray.length} changelists... ---`);

    clArray.forEach(cl => {
        const cmd = `p4 describe -s ${cl}`;
        // Note: Using SOURCE_WORKSPACE as a base to run describe
        const output = runP4Command(cmd, SOURCE_WORKSPACE);
        
        if (output) {
            const lines = output.split('\n');
            lines.forEach(line => {
                line = line.trim();
                if (line.startsWith('... //')) {
                    const match = line.match(/\.\.\.\s+(.+?)#\d+\s+(\S+)$/);
                    if (match) {
                        let depotPath = match[1]; 
                        let action = match[2];
                        
                        if (['add', 'edit', 'delete', 'branch', 'integrate', 'move/add', 'move/delete'].includes(action)) {
                            const isDeleteAction = (action === 'delete' || action === 'move/delete');
                            let finalAction = isDeleteAction ? 'delete' : (action === 'add' || action === 'move/add' ? 'add' : 'edit');
                            
                            if (!fileActions.has(depotPath)) {
                                fileActions.set(depotPath, finalAction);
                                console.log(`Found [NEW]: ${finalAction} ${depotPath} in CL:${cl}`);
                            } else if (isDeleteAction) {
                                fileActions.set(depotPath, 'delete');
                                console.warn(`Found [DELETE OVERWRITE]: delete ${depotPath} in CL:${cl}`);
                            }
                        }
                    }
                }
            });
        }
    });
    return Array.from(fileActions, ([depotPath, action]) => ({ depotPath, action }));
}

function convertDepotToLocal(depotPath, workspace) {
    const cmdWhere = `p4 where "${depotPath}"`; 
    const outputWhere = runP4Command(cmdWhere, workspace);
    if (outputWhere) {
        const parts = outputWhere.trim().split(/\s+/);
        if (parts.length >= 3) return parts[2]; 
    }
    return null; 
}

function createTargetChangelist(targetWorkspace) {
    console.log(`--- Creating new Changelist on Target (${targetWorkspace})... ---`);
    const cmd = `p4 --field "Description=${NEW_CL_DESCRIPTION}" change -o | p4 change -i`;
    const output = runP4Command(cmd, targetWorkspace);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        if (match) return match[1];
    }
    return null;
}

// ================= MAIN LOGIC =================

async function main() {
    console.log("=== STARTING MERGE PROCESS ===");

    // 1. Sync all 4 workspaces
    const workspacesToSync = [
        SOURCE_WORKSPACE, 
        COMBAT_LUA_SOURCE_WORKSPACE, 
        CLIENT_TARGET_WORKSPACE, 
        COMBAT_LUA_TARGET_WORKSPACE
    ];

    for (const ws of workspacesToSync) {
        if (!syncSourceToLatest(ws)) {
            console.error(`[ERROR] Failed to synchronize workspace ${ws}. Aborting.`);
            return;
        }
    }

    // 2. Read CLs
    const cls = getChangelistNumbers(CHANGE_LIST_FILE);
    if (cls.length === 0) {
        console.log("No CLs to process.");
        return;
    }

    // 3. Get file list
    const changedFileObjects = getChangedFilesFromCLs(cls);
    if (changedFileObjects.length === 0) return;

    const clMap = {}; 

    // Helper to get Context (Source & Target) based on path
    function getFileContext(depotPath) {
        // if (depotPath.toLowerCase().includes('combat_lua')) {
        //     return { 
        //         type: 'COMBAT_LUA', 
        //         srcWorkspace: COMBAT_LUA_SOURCE_WORKSPACE, 
        //         targetWorkspace: COMBAT_LUA_TARGET_WORKSPACE 
        //     };
        // }
        return { 
            type: 'CLIENT', 
            srcWorkspace: SOURCE_WORKSPACE, 
            targetWorkspace: CLIENT_TARGET_WORKSPACE 
        };
    }

    // 4. Process each file
    let successCount = 0;
    for (const fileObj of changedFileObjects) {
        const depotFile = fileObj.depotPath;
        const action = fileObj.action;
        
        const context = getFileContext(depotFile);
        const srcWorkspace = context.srcWorkspace;
        const targetWorkspace = context.targetWorkspace;
        const targetType = context.type;

        try {
            // A. Create CL for target if needed
            if (!clMap[targetType]) {
                const newCL = createTargetChangelist(targetWorkspace);
                if (!newCL) throw new Error(`Could not create Changelist for ${targetType}`);
                clMap[targetType] = newCL;
                console.log(`>> Target CL created for ${targetType}: ${newCL}`);
            }
            const targetCL = clMap[targetType];

            // B. Resolve Local Paths
            const sourceLocalPath = convertDepotToLocal(depotFile, srcWorkspace);
            if (!sourceLocalPath) {
                console.warn(`[SKIP] Could not map depot path to source workspace: ${depotFile}`);
                continue;
            }

            // Calculate relative path from Source Workspace root
            const relativePath = path.relative(srcWorkspace, sourceLocalPath);
            const targetLocalPath = path.join(targetWorkspace, relativePath);
            
            // C. Handle Delete
            if (action === 'delete') {
                if (fs.existsSync(targetLocalPath)) {
                    runP4Command(`p4 delete -c ${targetCL} "${targetLocalPath}"`, targetWorkspace);
                    try { fs.unlinkSync(targetLocalPath); } catch (e) {}
                    console.log(`[OK] Deleted (${targetType}): ${relativePath}`);
                    successCount++;
                } else {
                    console.warn(`[SKIP] Delete ignored (not found in target): ${relativePath}`);
                }
                continue;
            }

            // D. Handle Add/Edit
            if (!fs.existsSync(sourceLocalPath)) {
                console.warn(`[SKIP] Source file missing: ${sourceLocalPath}`);
                continue;
            }

            const targetDir = path.dirname(targetLocalPath);
            if (!fs.existsSync(targetDir)) fs.mkdirSync(targetDir, { recursive: true });

            if (fs.existsSync(targetLocalPath)) {
                fs.chmodSync(targetLocalPath, 0o666); 
                runP4Command(`p4 edit -c ${targetCL} "${targetLocalPath}"`, targetWorkspace);
            }
            
            fs.copyFileSync(sourceLocalPath, targetLocalPath);
            runP4Command(`p4 reconcile -c ${targetCL} -a -e "${targetLocalPath}"`, targetWorkspace);

            console.log(`[OK] Merged (${targetType}): ${relativePath}`);
            successCount++;

        } catch (err) {
            console.error(`[ERROR] Processing ${depotFile}: ${err.message}`);
        }
    }

    console.log("=== COMPLETE ===");
    console.log(`Merged ${successCount}/${changedFileObjects.length} files into CLs: ${JSON.stringify(clMap)}.`);
}

main();
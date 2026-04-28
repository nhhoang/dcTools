const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m"
};

const originalWarn = console.warn;
const originalError = console.error;
const originalLog = console.log;

console.warn = (...args) => originalWarn(colors.yellow + "[WARNING]", ...args, colors.reset);
console.error = (...args) => originalError(colors.red + "[ERROR]", ...args, colors.reset);
console.log = (...args) => originalLog(colors.cyan, ...args, colors.reset);

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { validateChangelistArray } = require('./changelistValidator');

// ================= CONFIGURATION =================
const CHANGE_LIST_FILE = path.resolve(__dirname, 'changelists.txt');

const SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'D:/Perforce/source_merge_client' 
    : '/Users/hoangnguyen/Perforce/MacbookPro'; 
const COMBAT_LUA_SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'D:/Perforce/source_merge_client_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Combat_Lua';

const CLIENT_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'D:/Perforce/merge_target_client' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Client'; 
const COMBAT_LUA_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'D:/Perforce/merge_target_combat_lua' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Combat_Lua';

const NEW_CL_DESCRIPTION = 'Auto merge files from Source to Target based on CLs';

// ================= HELPER FUNCTIONS =================

function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 100 
        });
        return output; 
    } catch (error) {
        console.error(`[ERROR] Command failed: ${command}`);
        return null;
    }
}

function syncSourceToLatest(workspace) {
    console.log(`--- Syncing Workspace (${workspace}) ---`);
    const output = runP4Command(`p4 sync //...`, workspace); 
    return output !== null;
}

function getChangelistNumbers(filePath) {
     if (!fs.existsSync(filePath)) return [];
     const content = fs.readFileSync(filePath, 'utf8');
     const cls = content.split(/\r?\n/).map(l => l.trim()).filter(l => l && !isNaN(l));
     const uniqueCls = [...new Set(cls)];
     const { validCls, warnings } = validateChangelistArray(uniqueCls, SOURCE_WORKSPACE);
     warnings.forEach(w => console.warn(w));
     return validCls;
}

function getChangedFilesFromCLs(clArray) {
    const fileActions = new Map(); 
    clArray.forEach(cl => {
        const output = runP4Command(`p4 describe -s ${cl}`, SOURCE_WORKSPACE);
        if (output) {
            const lines = output.split(/\r?\n/);
            lines.forEach(line => {
                line = line.trim();
                // Regex bắt Depot Path có dấu cách: ... //depot/path/file name.txt#1 action
                const match = line.match(/^\.\.\.\s+(.+?)#\d+\s+(\S+)$/);
                if (match) {
                    const depotPath = match[1].trim(); 
                    const action = match[2].trim();
                    const isDelete = ['delete', 'move/delete'].includes(action);
                    const finalAction = isDelete ? 'delete' : (['add', 'move/add'].includes(action) ? 'add' : 'edit');
                    if (!fileActions.has(depotPath) || isDelete) {
                        fileActions.set(depotPath, finalAction);
                    }
                }
            });
        }
    });
    return Array.from(fileActions, ([depotPath, action]) => ({ depotPath, action }));
}

/**
 * FIX CHÍNH TẠI ĐÂY:
 * Sử dụng -Ztag để lấy chính xác trường "path" (Local Path)
 */
function convertDepotToLocal(depotPath, workspace) {
    const output = runP4Command(`p4 -Ztag where "${depotPath}"`, workspace);
    if (output) {
        const lines = output.split(/\r?\n/);
        // Trong -Ztag, Local Path nằm ở dòng bắt đầu bằng "... path "
        const pathLine = lines.find(l => l.startsWith('... path '));
        if (pathLine) {
            let localPath = pathLine.replace('... path ', '').trim();
            return path.normalize(localPath);
        }
    }
    return null; 
}

function createTargetChangelist(targetWorkspace) {
    const output = runP4Command(`p4 --field "Description=${NEW_CL_DESCRIPTION}" change -o | p4 change -i`, targetWorkspace);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        return match ? match[1] : null;
    }
    return null;
}

// ================= MAIN LOGIC =================

async function main() {
    console.log("=== STARTING MERGE PROCESS ===");

    const workspaces = [SOURCE_WORKSPACE, COMBAT_LUA_SOURCE_WORKSPACE, CLIENT_TARGET_WORKSPACE, COMBAT_LUA_TARGET_WORKSPACE];
    for (const ws of workspaces) {
        if (!syncSourceToLatest(ws)) return;
    }

    const cls = getChangelistNumbers(CHANGE_LIST_FILE);
    const changedFileObjects = getChangedFilesFromCLs(cls);
    if (changedFileObjects.length === 0) return;

    const clMap = {}; 

    for (const fileObj of changedFileObjects) {
        const { depotPath: depotFile, action } = fileObj;
        const isCombat = depotFile.toLowerCase().includes('combat_lua');
        const srcWorkspace = isCombat ? COMBAT_LUA_SOURCE_WORKSPACE : SOURCE_WORKSPACE;
        const targetWorkspace = isCombat ? COMBAT_LUA_TARGET_WORKSPACE : CLIENT_TARGET_WORKSPACE;
        const targetType = isCombat ? 'COMBAT_LUA' : 'CLIENT';

        try {
            if (!clMap[targetType]) {
                clMap[targetType] = createTargetChangelist(targetWorkspace);
                console.log(`>> Target CL created for ${targetType}: ${clMap[targetType]}`);
            }
            const targetCL = clMap[targetType];

            const sourceLocalPath = convertDepotToLocal(depotFile, srcWorkspace);
            if (!sourceLocalPath) continue;

            const relativePath = path.relative(srcWorkspace, sourceLocalPath);
            const targetLocalPath = path.join(targetWorkspace, relativePath);
            
            if (action === 'delete') {
                runP4Command(`p4 delete -c ${targetCL} "${targetLocalPath}"`, targetWorkspace);
                console.log(`[OK] Deleted: ${relativePath}`);
            } else {
                if (!fs.existsSync(sourceLocalPath)) {
                    console.warn(`[SKIP] Missing source: "${sourceLocalPath}"`);
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
                console.log(`[OK] Merged: ${relativePath}`);
            }
            successCount = (global.successCount || 0) + 1;
        } catch (err) {
            console.error(`[ERROR] ${depotFile}: ${err.message}`);
        }
    }
    console.log("=== COMPLETE ===");
}

main();
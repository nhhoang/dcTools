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
// Absolute path to the file containing the list of CLs
const CHANGE_LIST_FILE = path.resolve(__dirname, 'changelists.txt');
const FILE_PATHS = [
    "//dcwc/Gear_Character_Development_Config/excel/Enemy.csv",
    "//dcwc/Gear_Character_Development_Config/excel/BadgeRoute.csv",
    "//dcwc/Gear_Character_Development_Config/excel/SkillMonster.csv",
    "//dcwc/Gear_Character_Development_Config/excel/BadgeSkill.csv",
    "//dcwc/Gear_Character_Development_Config/excel/BuffTemplate.csv",
    "//dcwc/Gear_Character_Development_Config/excel/EnemyTower.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Skill.csv",
    "//dcwc/Gear_Character_Development_Config/excel/AllyInfo.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Avatar.csv",
    "//dcwc/Gear_Character_Development_Config/excel/CharacterProfile.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Profile.csv",
    "//dcwc/Gear_Character_Development_Config/excel/TrialChapter.csv",
    "//dcwc/Gear_Character_Development_Config/excel/TrialLevel.csv",
    "//dcwc/Gear_Character_Development_Config/excel/AllyPassiveRelation.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Language/SourceBattleDesc.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Language/SourceCommonDesc.csv",
    "//dcwc/Gear_Character_Development_Config/excel/AllyActiveRelation.csv",
    "//dcwc/Gear_Character_Development_Config/excel/Skills/SkillTacticalResonance.csv"
]

// Absolute path to the 2 Workspaces
// Note: Use forward slashes (/) or double backslashes (\\) for Windows paths
const SOURCE_WORKSPACE = '/Users/hoangnguyen/Perforce/MacbookPro_Config'; 
const CLIENT_TARGET_WORKSPACE = '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Config';
const COMBAT_LUA_TARGET_WORKSPACE = '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Combat_Lua';

// Description for the new Change List to be created
const NEW_CL_DESCRIPTION = 'Auto merge files from Source to Target based on CLs';

// ================= HELPER FUNCTIONS =================

/**
 * Syncs the specified Workspace to the latest revision.
 */
function syncSourceToLatest(workspace) {
    console.log(`--- Syncing Workspace (${workspace}) to the latest revision... ---`);
    
    // The p4 sync //... command syncs the entire workspace to the head revision
    const cmd = `p4 sync //...`; 
    
    // Using runP4Command with workspace as CWD (root directory)
    const output = runP4Command(cmd, workspace); 
    
    if (output != null) {
        // Find the first line with file info (if any) or a completion message
        const syncMessage = output.split('\n').find(line => line.includes('...')) || 'Sync completed successfully.';
        console.log(`[P4 SYNC OK] ${syncMessage}`);
        return true;
    }
    
    // If runP4Command returned null (due to error trapping in its try-catch block)
    console.error(`[ERROR] Failed to sync workspace: ${workspace}`);
    return false;
}

/**
 * Executes a P4 command in the specified directory to recognize .p4config
 */
function runP4Command(command, cwd) {
    try {
        // maxBuffer to avoid errors if the output is too long
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 10 // 10MB buffer
        });
        return output.trim();
    } catch (error) {
        console.error(`[ERROR] Failed to run command: ${command} at ${cwd}`);
        console.error(error.message);
        return null;
    }
}

/**
 * Reads changelists.txt file and returns an array of numbers
 */
function getChangelistNumbers(filePath) {
    if (!fs.existsSync(filePath)) {
        console.error(`[ERROR] File not found: ${filePath}`);
        return [];
    }
    const content = fs.readFileSync(filePath, 'utf8');
    
    // 1. Split lines, trim whitespace, and filter out non-numeric lines
    const cls = content.split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0 && !isNaN(line));
    
    // 2. Use Set to remove duplicates
    const uniqueCls = [...new Set(cls)];

    // 3. Sort from smallest to largest
    // Cast to Number to ensure correct numeric comparison (a - b)
    return uniqueCls.sort((a, b) => Number(a) - Number(b));
}

/**
 * Gets the list of changed files (Depot Path) from CLs, removing duplicates,
 * along with their action type (add, edit, delete, etc.).
 */
function getChangedFilesFromCLs(clArray) {
    const fileActions = new Map(); // Key: DepotPath, Value: Action (e.g., 'edit', 'delete')
    FILE_PATHS.forEach(filePath => {
        fileActions.set(filePath, 'edit');
    });

    // Return an array of objects for easier processing: [{ depotPath: '...', action: '...' }]
    return Array.from(fileActions, ([depotPath, action]) => ({ depotPath, action }));
}


// Function to convert depot path to local path
function convertDepotToLocal(depotPath, workspace) {
    // p4 where returns 3 parts: depot path, client path, local path
    // Example output: //depot/path/file //client/path/file C:\workspace\local\path\file
    const cmdWhere = `p4 where "${depotPath}"`; 
    const outputWhere = runP4Command(cmdWhere, workspace);

    if (outputWhere) {
        // Split the output string. The output is typically 3 space-separated parts.
        const parts = outputWhere.trim().split(/\s+/);
        
        // The local path is the 3rd element (index 2)
        // Check if there are at least 3 parts
        if (parts.length >= 3) {
            // parts[2] is the Local Path
            return parts[2]; 
        }
    }
    return null; // Return null if not found or error occurred
}

/**
 * Finds the local path of the file in the Source Workspace
 * Uses 'p4 where' command to map from Depot Path -> Local Path
 */
function getLocalSourcePath(depotPath) {
    const localPath = convertDepotToLocal(depotPath, SOURCE_WORKSPACE);

    return localPath;
}

/**
 * Creates a new Change List in the specified Target Workspace
 */
function createTargetChangelist(targetWorkspace) {
    console.log(`--- Creating new Changelist on Target (${targetWorkspace})... ---`);
    
    // Create specification for the change list
    const cmd = `p4 --field "Description=${NEW_CL_DESCRIPTION}" change -o | p4 change -i`;
    
    const output = runP4Command(cmd, targetWorkspace);
    // Example Output: "Change 123456 created."
    if (output) {
        const match = output.match(/Change (\d+) created/);
        if (match) {
            return match[1];
        }
    }
    return null;
}

// ================= MAIN LOGIC =================

async function main() {
    console.log("=== STARTING MERGE PROCESS ===");

    // 1. Synchronize all workspaces once at the beginning
    if (!syncSourceToLatest(SOURCE_WORKSPACE) || 
        !syncSourceToLatest(CLIENT_TARGET_WORKSPACE) || 
        !syncSourceToLatest(COMBAT_LUA_TARGET_WORKSPACE)) {
        console.error("[ERROR] Failed to synchronize one or more workspaces. Aborting process.");
        return;
    }

    // 2. Read CLs
    const cls = getChangelistNumbers(CHANGE_LIST_FILE);
    if (cls.length === 0) {
        console.log("No CLs to process.");
        return;
    }
    console.log(`Found CLs: ${cls.join(', ')}`);

    // 3. Get list of changed files and their actions (Depot Path)
    const changedFileObjects = getChangedFilesFromCLs(cls);
    console.log(`Total of ${changedFileObjects.length} unique changed files found.`);

    if (changedFileObjects.length === 0) return;

    // 4. Initialize separate CLs for each Target Workspace
    // We create CLs lazily (on first file for that workspace) or upfront.
    // For simplicity, let's track the CLs created for each type:
    const clMap = {}; // { 'CLIENT': CL_Number, 'COMBAT_LUA': CL_Number }

    // Helper function to get the correct CL and Workspace based on file path
    function getTargetContext(depotPath) {
        // Detect 'combat_lua' files
        // if (depotPath.toLowerCase().includes('combat_lua')) {
        //     return { type: 'COMBAT_LUA', workspace: COMBAT_LUA_TARGET_WORKSPACE };
        // }
        // All other files go to CLIENT
        return { type: 'CLIENT', workspace: CLIENT_TARGET_WORKSPACE };
    }


    // 5. Process each file: Copy/Delete from Source -> Target and Add to CL
    let successCount = 0;
    
    for (const fileObj of changedFileObjects) {
        const depotFile = fileObj.depotPath;
        const action = fileObj.action;
        
        // Determine the target context for this specific file
        const context = getTargetContext(depotFile);
        const targetWorkspace = context.workspace;
        const targetType = context.type;

        try {
            // A. Create CL if not exists for this Target type
            if (!clMap[targetType]) {
                const newCL = createTargetChangelist(targetWorkspace);
                if (!newCL) throw new Error(`Could not create Changelist for ${targetType}`);
                clMap[targetType] = newCL;
                console.log(`>> Target CL created for ${targetType}: ${newCL}`);
            }
            const targetCL = clMap[targetType];

            // B. Calculate Target Local Path (Needed for all operations, including Delete)
            const sourceLocalPath = getLocalSourcePath(depotFile);
            
            // Logic: Get relative path from Source Root, then join to Target Root
            const relativePath = path.relative(SOURCE_WORKSPACE, sourceLocalPath || '');
            const targetLocalPath = path.join(targetWorkspace, relativePath);
            
            
            // ================== HANDLE DELETE ACTION ==================
            if (action === 'delete') {
                // If the file exists locally in the Target workspace, mark it for delete
                if (fs.existsSync(targetLocalPath)) {
                    runP4Command(`p4 delete -c ${targetCL} "${targetLocalPath}"`, targetWorkspace);
                    
                    // (Optional) Remove the physical file after marking it for delete
                    try {
                        fs.unlinkSync(targetLocalPath); 
                    } catch (unlinkError) {
                        // Ignore if deletion failed (p4 delete already marks it on server)
                    }
                    console.log(`[OK] Deleted (${targetType}): ${relativePath}`);
                    successCount++;
                    continue; // Go to next file
                } else {
                    // File was deleted in Source but doesn't exist in Target (already deleted or not mapped)
                    console.warn(`[SKIP] Delete action for file ${depotFile} ignored (file not found in ${targetType} local path).`);
                    continue;
                }
            }
            // ================== END DELETE ACTION ==================


            // --- Processing for ADD/EDIT actions (Requires Copy) ---

            if (!sourceLocalPath || !fs.existsSync(sourceLocalPath)) {
                 // This should theoretically not happen for add/edit if sync was successful
                console.warn(`[SKIP] Local file not found in Source for ADD/EDIT: ${depotFile}`);
                continue;
            }

            // C. Ensure the parent directory exists on Target
            const targetDir = path.dirname(targetLocalPath);
            if (!fs.existsSync(targetDir)) {
                fs.mkdirSync(targetDir, { recursive: true });
            }

            // Step D1: Prepare the target file (Remove Read-Only attribute)
            if (fs.existsSync(targetLocalPath)) {
                // EXTREMELY IMPORTANT: Remove Read-Only attribute to allow copy
                try {
                    // 0o666 is Read/Write permissions
                    fs.chmodSync(targetLocalPath, 0o666); 
                    
                    // Try running p4 edit; if it fails, ignore (since Read-Only is removed by chmod)
                    try {
                        runP4Command(`p4 edit -c ${targetCL} "${targetLocalPath}"`, targetWorkspace);
                    } catch (editError) {
                        console.warn(`[WARNING] p4 edit failed for ${targetType}. Proceeding with Copy and Reconcile. Error: ${editError.message}`);
                    }

                } catch (chmodError) {
                    // If fs.chmodSync also fails (rare, unless file is locked by another app)
                    console.error(`[ERROR] Could not remove Read-Only attribute (chmod) for file: ${targetLocalPath}.`);
                    throw chmodError; // Throw error to interrupt processing for this file
                }
            }
            
            // Step D2: Physically copy the file
            fs.copyFileSync(sourceLocalPath, targetLocalPath);

            // Step D3: Add to P4 (Reconcile handles both New Add and Existing Edit cases)
            // -c: specify CL number
            // -a: add, -e: edit
            const reconcileCmd = `p4 reconcile -c ${targetCL} -a -e "${targetLocalPath}"`;
            runP4Command(reconcileCmd, targetWorkspace);

            console.log(`[OK] Merged (${targetType}): ${relativePath}`);
            successCount++;

        } catch (err) {
            console.error(`[ERROR] When processing file ${depotFile}: ${err.message}`);
        }
    }

    console.log("=== COMPLETE ===");
    console.log(`Successfully merged ${successCount}/${changedFileObjects.length} files into CLs: ${JSON.stringify(clMap)}.`);
    console.log("Please check the Target Workspaces before submitting.");
}

// Run the script
main();
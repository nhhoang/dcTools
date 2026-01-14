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

const fs = require('fs'); // Use native fs module only
const path = require('path');
const { execSync } = require('child_process');

// ================= CONFIGURATION =================
const SOURCE_WORKSPACE = 'C:/Users/hoang/Perforce/Company_Windows'; 
const TARGET_WORKSPACE = 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client'; 
const JSON_FILE = 'liveopsEvents.json';
const NEW_CL_DESCRIPTION = "Auto-generated CL for LiveOps Events";
const TARGET_TYPE = 'LIVE_OPS_ASSETS'; 


// --- TEMPLATE PATHS (Unchanged) ---
const COMMON_CHARACTER_PATHS = [
    "Assets/Res/LoadUITexture/Banner#CHARACTER_ID",
    "Assets/Res/LoadUITexture/Banner#CHARACTER_ID.meta",
    "Assets/Res/UI/DrawCardToggleTex/in_atlas/ui_drawcard_btn_#CHARACTER_ID.png",
    "Assets/Res/UI/DrawCardToggleTex/in_atlas/ui_drawcard_btn_#CHARACTER_ID.png.meta",
    "Assets/Res/UI/DrawCardToggleTex/drawcardtoggletex_atlas.spriteatlas",
    "Assets/Res/UI/DrawCardToggleTex/drawcardtoggletex_atlas.spriteatlas.meta",
    "Assets/Res/UI/IconTexture/Badge01/ui_badge_icon_#CHARACTER_ID.png",
    "Assets/Res/UI/IconTexture/Badge01/ui_badge_icon_#CHARACTER_ID.png.meta",
    "Assets/Res/UI/IconTexture/Badge02/ui_badge_icon_#CHARACTER_ID.png",
    "Assets/Res/UI/IconTexture/Badge02/ui_badge_icon_#CHARACTER_ID.png.meta",
    "Assets/Res/UI/IconTexture/BadgeMid/in_atlas/ui_badge_icon_#CHARACTER_ID_mid.png",
    "Assets/Res/UI/IconTexture/BadgeMid/in_atlas/ui_badge_icon_#CHARACTER_ID_mid.png.meta",
    "Assets/Res/UI/IconTexture/heroheadBig/ui_icon_heroheadBig#CHARACTER_ID.png",
    "Assets/Res/UI/IconTexture/heroheadBig/ui_icon_heroheadBig#CHARACTER_ID.png.meta",
    "Assets/Res/UI/IconTexture/Profile/ui_profile_#CHARACTER_ID.png",
    "Assets/Res/UI/IconTexture/Profile/ui_profile_#CHARACTER_ID.png.meta",
    "Assets/Res/UI/NonReusable/CardPool_#CHARACTER_ID",
    "Assets/Res/UI/NonReusable/CardPool_#CHARACTER_ID.meta",
    "Assets/Res/UI/NonReusable/DrawCard#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/DrawCard#CHARACTER_IDTex.meta",
    "Assets/Res/UI/NonReusable/PopupPic_#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/PopupPic_#CHARACTER_IDTex.meta",
    "Assets/Res/UI/NonReusable/Recharge#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/Recharge#CHARACTER_IDTex.meta",
    "Assets/Res/UI/StoreIAPPackTex/IAPPack_#CHARACTER_ID",
    "Assets/Res/UI/StoreIAPPackTex/IAPPack_#CHARACTER_ID.meta"
];

const EPIC_EXTRA = [
    "Assets/Res/UI/NonReusable/Bingo#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/Bingo#CHARACTER_IDTex.meta"
];

const LEGENDARY_EXTRA = [
    "Assets/Res/UI/NonReusable/ActivityAlly#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/ActivityAlly#CHARACTER_IDTex.meta",
    "Assets/Res/UI/NonReusable/TrailerBG#CHARACTER_IDTex",
    "Assets/Res/UI/NonReusable/TrailerBG#CHARACTER_IDTex.meta",
    "Assets/Res/Prefabs/UI/ActivityAlly/#CHARACTER_NAME",
    "Assets/Res/Prefabs/UI/ActivityAlly/#CHARACTER_NAME.meta"
];

const REINFORCEMENT_PATHS = [
    "Assets/Res/LoadUITexture/Banner#REINFORCEMENT_ID",
    "Assets/Res/LoadUITexture/Banner#REINFORCEMENT_ID.meta",
    "Assets/Res/UI/NonReusable/Recharge#REINFORCEMENT_IDTex",
    "Assets/Res/UI/NonReusable/Recharge#REINFORCEMENT_IDTex.meta"
];

const ARTIFACT_PATHS = [
    "Assets/Res/UI/IconTexture/ArtifactBig/Artifact_Large_#ARTIFACT_ID.png",
    "Assets/Res/UI/IconTexture/ArtifactBig/Artifact_Large_#ARTIFACT_ID.png.meta",
    "Assets/Res/UI/IconTexture/ArtifactMid/Artifact_Middle_#ARTIFACT_ID.png",
    "Assets/Res/UI/IconTexture/ArtifactMid/Artifact_Middle_#ARTIFACT_ID.png.meta",
    "Assets/Res/UI/IconTexture/ArtifactSmall/in_atlas/Artifact_Small_#ARTIFACT_ID.png",
    "Assets/Res/UI/IconTexture/ArtifactSmall/in_atlas/Artifact_Small_#ARTIFACT_ID.png.meta",
    "Assets/Res/UI/IconTexture/items02/Artifact_Fragment_#ARTIFACT_ID.png",
    "Assets/Res/UI/IconTexture/items02/Artifact_Fragment_#ARTIFACT_ID.png.meta"
];


// ================= P4 HELPER FUNCTIONS (Unchanged) =================

function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 10
        });
        return output.trim();
    } catch (error) {
        const errorMessage = error.stderr ? error.stderr.toString().trim() : error.message;
        console.error(`[ERROR] Failed to run command: ${command} at ${cwd}`);
        console.error(`[P4 Error] Error message: ${errorMessage}`);
        return null;
    }
}

function syncWorkspaceToLatest(workspace) {
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

function createTargetChangelist(targetWorkspace) {
    console.log(`--- Creating new Changelist on Target (${targetWorkspace})... ---`);
    
    try {
        const cmd = `p4 --field "Description=${NEW_CL_DESCRIPTION}" change -o | p4 change -i`;
        const output = runP4Command(cmd, targetWorkspace);
        
        if (output) {
            const match = output.match(/Change (\d+) created/);
            if (match) {
                return match[1];
            }
        }
        return null;
    } catch (e) {
         console.error(`[ERROR] Failed to create Changelist.`);
         return null;
    }
}

/**
 * Gets a list of all files in a directory (recursively)
 */
function getFilesRecursively(dir) {
    let results = [];
    const list = fs.readdirSync(dir);

    list.forEach(file => {
        file = path.join(dir, file);
        const stat = fs.statSync(file);
        
        if (stat && stat.isDirectory()) { 
            results = results.concat(getFilesRecursively(file));
        } else { 
            results.push(file);
        }
    });

    return results;
}

/**
 * Copies a folder recursively (manual implementation)
 */
function copyFolderRecursiveSync(src, dest) {
    // *** Target directory creation ensured before copying ***
    fs.mkdirSync(dest, { recursive: true });

    const files = fs.readdirSync(src);

    files.forEach(item => {
        const srcItem = path.join(src, item);
        const destItem = path.join(dest, item);
        const stat = fs.statSync(srcItem);

        if (stat.isDirectory()) {
            copyFolderRecursiveSync(srcItem, destItem);
        } else {
            if (fs.existsSync(destItem)) {
                fs.chmodSync(destItem, 0o666); // Remove Read-Only
            }
            fs.copyFileSync(srcItem, destItem);
        }
    });
}


// ================= MAIN LOGIC (Refined) =================

async function main() {
    console.log("=== STARTING LIVE OPS ASSET COPY PROCESS ===");

    // 1. Synchronize Workspaces
    if (!syncWorkspaceToLatest(SOURCE_WORKSPACE) || !syncWorkspaceToLatest(TARGET_WORKSPACE)) {
        console.error("[ERROR] Failed to synchronize one or more workspaces. Aborting process.");
        return;
    }

    // 2. Read and Parse JSON
    if (!fs.existsSync(JSON_FILE)) {
        console.error(`[ERROR] JSON file not found: ${JSON_FILE}`);
        return;
    }
    let data;
    try {
        data = JSON.parse(fs.readFileSync(JSON_FILE));
    } catch (e) {
        console.error(`[ERROR] Failed to parse JSON file: ${JSON_FILE}. Error: ${e.message}`);
        return;
    }
    
    let allPaths = [];

    // 3. Generate list of paths (Unchanged)
    ['epic', 'legendary'].forEach(tier => {
        if (Array.isArray(data.character?.[tier])) {
            data.character[tier].forEach(char => {
                let tpls = [...COMMON_CHARACTER_PATHS, ...(tier === 'epic' ? EPIC_EXTRA : LEGENDARY_EXTRA)];
                tpls.forEach(t => allPaths.push(t.replace(/#CHARACTER_ID/g, char.id).replace(/#CHARACTER_NAME/g, char.name)));
            });
        }
    });
    if (Array.isArray(data.reinforcement)) {
        data.reinforcement.forEach(item => {
            REINFORCEMENT_PATHS.forEach(t => allPaths.push(t.replace(/#REINFORCEMENT_ID/g, item.id)));
        });
    }
    if (Array.isArray(data.artifact)) {
        data.artifact.forEach(item => {
            ARTIFACT_PATHS.forEach(t => allPaths.push(t.replace(/#ARTIFACT_ID/g, item.id)));
        });
    }

    const uniquePaths = [...new Set(allPaths)];
    console.log(`Found ${uniquePaths.length} unique file/folder paths from ${JSON_FILE}.`);

    if (uniquePaths.length === 0) return;

    // 4. Create CL for Target
    const targetCL = createTargetChangelist(TARGET_WORKSPACE);
    if (!targetCL) {
        console.error("[ERROR] Aborting due to CL creation failure.");
        return;
    }
    console.log(`>> Target CL created: ${targetCL}`);


    // 5. Process each path: Copy from Source -> Target and Reconcile
    let totalSuccessCount = 0;
    
    for (const relativePath of uniquePaths) {
        const srcPath = path.join(SOURCE_WORKSPACE, relativePath);
        const destPath = path.join(TARGET_WORKSPACE, relativePath);

        try {
            if (!fs.existsSync(srcPath)) {
                console.warn(`[SKIP] Path not found in source: ${relativePath}`);
                continue;
            }

            const stat = fs.statSync(srcPath);

            if (stat.isDirectory()) {
                // ============== FOLDER PROCESSING ==============
                console.log(`[FOLDER] Processing folder: ${relativePath}`);
                
                // 1. Recursive Copy (Logic for folder creation included in the function)
                copyFolderRecursiveSync(srcPath, destPath);

                // 2. Get list of all copied files
                const copiedFiles = getFilesRecursively(destPath);
                
                // 3. Reconcile each file in the target directory
                copiedFiles.forEach(file => {
                    // Remove Read-Only attribute before reconcile (necessary for existing files)
                    try {
                        // Note: fs.chmodSync(file, 0o666) is called inside copyFolderRecursiveSync
                        // but called again here to ensure for previously existing files.
                        fs.chmodSync(file, 0o666); 
                        // Use reconcile to detect add/edit
                        runP4Command(`p4 reconcile -c ${targetCL} -a -e "${file}"`, TARGET_WORKSPACE);
                        totalSuccessCount++;
                    } catch (p4Error) {
                        // console.warn(`[WARNING] Failed to reconcile file inside folder: ${path.relative(TARGET_WORKSPACE, file)}`);
                    }
                });

                console.log(`[OK] Copied and reconciled contents of folder: ${relativePath}`);

            } else {
                // ============== SINGLE FILE PROCESSING ==============
                
                // *** Ensure parent directory is created before copying file ***
                const targetDir = path.dirname(destPath);
                fs.mkdirSync(targetDir, { recursive: true });
                
                // Prepare Target file (only if file exists)
                if (fs.existsSync(destPath)) {
                    // Remove Read-Only attribute
                    fs.chmodSync(destPath, 0o666); 
                    
                    // Attempt 'p4 edit'
                    try {
                        runP4Command(`p4 edit -c ${targetCL} "${destPath}"`, TARGET_WORKSPACE);
                    } catch (editError) { /* Ignore if edit fails */ }
                }
                
                // Physically copy the file
                fs.copyFileSync(srcPath, destPath);

                // Reconcile (Add/Edit)
                const reconcileCmd = `p4 reconcile -c ${targetCL} -a -e "${destPath}"`;
                runP4Command(reconcileCmd, TARGET_WORKSPACE);

                console.log(`[OK] Copied and Added to CL: ${relativePath}`);
                totalSuccessCount++;
            }
        } catch (err) {
            console.error(`[ERROR] When processing path ${relativePath}: ${err.message}`);
        }
    }

    console.log("=== COMPLETE ===");
    console.log(`Total files processed and reconciled: ${totalSuccessCount}`);
    console.log(`All files/folders are checked out/added in Changelist: ${targetCL}`);
    console.log(`Please check the Target Workspace before submitting.`);
}

// Run the script
main();
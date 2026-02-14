const { execSync } = require('child_process');

// ================= COLORS =================
const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m",
    green: "\x1b[32m"
};

// ================= CONFIGURATION =================
const PLATFORM = process.platform;
const IS_WIN = PLATFORM === 'win32';

// Base Configs
const BASE_CONFIGS = {
    CLIENT: {
        workspace: IS_WIN ? 'Desktop_Merge_Target_Client' : 'MacbookPro_Merge_Target_Client',
        cwd: IS_WIN ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client' : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Client',
        streams: {
            staging: '//dcwc/Gear_Character_Staging_Client',
            trunk:   '//dcwc/trunk',
            patch:   '//dcwc/v1_1_14_10_Patch_A_Assets',
            parent:  '//dcwc/v1_1_14_Parent_Client'
        }
    },
    COMBAT_LUA: {
        workspace: IS_WIN ? 'Desktop_Merge_Target_Combat_Lua' : 'MacbookPro_Merge_Target_Combat_Lua',
        cwd: IS_WIN ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Combat_Lua' : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Combat_Lua',
        streams: {
            staging: '//dcwc/Gear_Character_Staging_Combat_Lua',
            trunk:   '//dcwc/combat_lua',
            patch:   '//dcwc/v1_1_14_10_Patch_A_Combat_Lua',
            parent:  '//dcwc/v1_1_14_Parent_Combat_Lua'
        }
    },
    CONFIG: {
        workspace: IS_WIN ? 'Desktop_Merge_Target_Config' : 'MacbookPro_Merge_Target_Config',
        cwd: IS_WIN ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Config' : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Config',
        streams: {
            staging: '//dcwc/Gear_Character_Staging_Config',
            trunk:   '//dcwc/config',
            patch:   '//dcwc/v1_1_14_10_Patch_A_Config',
            parent:  '//dcwc/v1_1_14_Parent_Config'
        }
    }
};

const CL_DESCRIPTION = '14.10: Merging ';

// ================= UTILS =================

function log(msg, color = colors.reset) {
    console.log(color + msg + colors.reset);
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
        log(`[ERROR] Failed to run command: ${command} at ${cwd}`, colors.red);
        log(error.message, colors.red);
        return null;
    }
}

function createCL(from, to, config) {
    const cmd = `p4 --field "Description=${CL_DESCRIPTION} ${from} to ${to}" change -o | p4 -c ${config.workspace} change -i`;
    const output = runP4Command(cmd, config.cwd);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        return match ? match[1] : null;
    }
    return null;
}

function integrateStream(sourceStream, targetStream, config) {
    log(`\n>>> 🔗 INTEGRATING: ${sourceStream} ➔ ${targetStream}`, colors.yellow);

    // 1. Switch Workspace
    log(`   Switching workspace to: ${targetStream}`);
    runP4Command(`p4 client -s -S ${targetStream}`, config.cwd);

    // 2. Sync
    log(`   Syncing target workspace to latest...`);
    runP4Command(`p4 sync`, config.cwd);

    // 3. Create CL
    const clId = createCL(sourceStream, targetStream, config);
    if (!clId) return;

    // 4. Integrate
    log(`   Running p4 integrate -i...`);
    const intCmd = `p4 integrate -c ${clId} -i "${sourceStream}/..." "${targetStream}/..."`;
    const result = runP4Command(intCmd, config.cwd);

    if (result && !result.includes("all revision(s) already integrated")) {
        log(`   ℹ️ Files opened in CL: ${clId}`, colors.cyan);
        
        // 5. Resolve
        log(`   Resolving files (Auto-Safe)...`);
        runP4Command(`p4 resolve -c ${clId} -am -dw`, config.cwd);
        
        log(`   ✨ Integration complete for ${targetStream}.`, colors.green);
    } else {
        log(`   ✅ No changes to integrate.`, colors.green);
        runP4Command(`p4 change -d ${clId}`, config.cwd);
    }
}

// ================= MAIN =================

async function main() {
    const args = process.argv.slice(2);
    const mode = args[0] ? args[0].toUpperCase() : 'ALL'; // 'CLIENT', 'COMBAT_LUA', 'CONFIG', or 'ALL'

    log("=== STARTING MERGE UP PROCESS ===", colors.cyan);

    // Define "Beads" (Tasks)
    const beads = [
        {
            id: 'CLIENT',
            name: 'Client Streams',
            run: () => processConfig('CLIENT')
        },
        {
            id: 'COMBAT_LUA',
            name: 'Combat Lua Streams',
            run: () => processConfig('COMBAT_LUA')
        },
        {
            id: 'CONFIG',
            name: 'Config Streams',
            run: () => processConfig('CONFIG')
        }
    ];

    // Filter beads based on mode
    const tasksToRun = (mode === 'ALL') 
        ? beads 
        : beads.filter(b => b.id === mode);

    if (tasksToRun.length === 0) {
        log(`[ERROR] No tasks found for mode: ${mode}`, colors.red);
        return;
    }

    // Execute Beads
    for (const bead of tasksToRun) {
        log(`\n🔵 BEAD: ${bead.name}`, colors.cyan);
        try {
            bead.run();
            log(`✅ BEAD COMPLETE: ${bead.name}`, colors.green);
        } catch (err) {
            log(`❌ BEAD FAILED: ${bead.name}`, colors.red);
            console.error(err);
        }
    }

    log("\n=== PROCESS COMPLETE ===", colors.cyan);
    log("Please check your changelists in P4V before submitting.");
}

function processConfig(key) {
    if (!BASE_CONFIGS[key]) {
        log(`[SKIP] Unknown config type: ${key}`, colors.red);
        return;
    }

    const config = BASE_CONFIGS[key];
    log(`>>> Processing: ${key}`, colors.yellow);

    // Step 1: Staging -> Trunk
    integrateStream(config.streams.staging, config.streams.trunk, config);

    // Step 2: Trunk -> Patch
    integrateStream(config.streams.trunk, config.streams.patch, config);
}

main();

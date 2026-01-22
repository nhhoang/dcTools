
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

const { execSync } = require('child_process');

// ================= CONFIGURATION =================
const COMBAT_LUA_WORKSPACE = 'Desktop_Merge_Target_Combat_Lua';
const CLIENT_WORKSPACE = 'Desktop_Merge_Target_Client';
const CONFIG_WORKSPACE = 'Desktop_Merge_Target_Config';
const COMBAT_LUA_WORKSPACE_PATH = process.platform === 'win32' ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Combat_Lua' : '/Users/hoangnguyen/Perforce/Desktop_Merge_Target_Combat_Lua'
const CLIENT_WORKSPACE_PATH = process.platform === 'win32' ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client' : '/Users/hoangnguyen/Perforce/Desktop_Merge_Target_Client'
const CONFIG_WORKSPACE_PATH = process.platform === 'win32' ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Config' : '/Users/hoangnguyen/Perforce/Desktop_Merge_Target_Config'

const COMBAT_LUA_SOURCE_STREAM = '//dcwc/v1_1_14_9_Patch_A_Combat_Lua_Revert1'
const COMBAT_LUA_TARGET_STREAM = '//dcwc/v1_1_14_10_Patch_A_Combat_Lua'

const CLIENT_SOURCE_STREAM = '//dcwc/v1_1_14_9_Patch_A_Assets_Revert1'
const CLIENT_TARGET_STREAM = '//dcwc/v1_1_14_10_Patch_A_Assets'
    
const CONFIG_SOURCE_STREAM = '//dcwc/v1_1_14_9_Patch_A_Config'
const CONFIG_TARGET_STREAM = '//dcwc/v1_1_14_10_Patch_A_Config'

const CL_DESCRIPTION = 'Auto integrate downstream with Sync';

// ================= HELPER FUNCTIONS =================

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

function createCL(workspace, workspacePath) {
    const cmd = `p4 --field "Description=${CL_DESCRIPTION}" change -o | p4 -c ${workspace} change -i`;
    const output = runP4Command(cmd, workspacePath);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        return match ? match[1] : null;
    }
    return null;
}

function integrateStream(sourceStream, targetStream, workspace, workspacePath) {
    console.warn(`\n>>> 🔗 INTEGRATING: ${sourceStream} ➔ ${targetStream}`);

    // 1. Chuyển Workspace sang Stream đích
    console.log(`   Switching workspace to: ${targetStream}`);
    runP4Command(`p4 client -s -S ${targetStream}`, workspacePath);

    // 2. GET LATEST (Sync) - Cập nhật code mới nhất cho branch đích
    console.log(`   Syncing target workspace to latest...`);
    runP4Command(`p4 sync`, workspacePath); // Tương đương p4 sync //...

    // 3. Tạo Changelist
    const clId = createCL(workspace, workspacePath);
    if (!clId) return;

    // 4. Chạy lệnh Integrate với cờ -i
    console.log(`   Running p4 integrate -i...`);
    const intCmd = `p4 integrate -c ${clId} -i "${sourceStream}/..." "${targetStream}/..."`;
    const result = runP4Command(intCmd, workspacePath);

    if (result && !result.includes("all revision(s) already integrated")) {
        console.log(`   ℹ️ Files opened in CL: ${clId}`);
        
        // 5. Resolve
        console.log(`   Resolving files (Auto-Safe)...`);
        runP4Command(`p4 resolve -c ${clId} -as`, workspacePath);
        
        console.log(`   ✨ Hoàn tất integrate vào ${targetStream}.`);
    } else {
        console.log(`   ✅ Không có thay đổi nào cần integrate hoặc đã up-to-date.`);
        runP4Command(`p4 change -d ${clId}`, workspacePath);
    }
}

// ================= MAIN LOGIC =================

function main() {
    console.log("=== BẮT ĐẦU QUY TRÌNH FINAL CHECK LIÊN HOÀN ===");

    // Bước 1: Combat lua
    integrateStream(COMBAT_LUA_SOURCE_STREAM, COMBAT_LUA_TARGET_STREAM, COMBAT_LUA_WORKSPACE, COMBAT_LUA_WORKSPACE_PATH);

    // Bước 2: Config
    integrateStream(CONFIG_SOURCE_STREAM, CONFIG_TARGET_STREAM, CONFIG_WORKSPACE, CONFIG_WORKSPACE_PATH);

    // Bước 3: Client
    integrateStream(CLIENT_SOURCE_STREAM, CLIENT_TARGET_STREAM, CLIENT_WORKSPACE, CLIENT_WORKSPACE_PATH);

    console.log("\n=== HOÀN THÀNH ===");
    console.log("Mời bạn kiểm tra các Changelist trong P4V trước khi Submit.");
}

main();

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
const MY_WORKSPACE = process.platform === 'win32' ? 'Desktop_Merge_Target_Combat_Lua' : 'MacbookPro_Merge_Target_Combat_Lua';
const WORKSPACE_PATH = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Combat_Lua';

const STREAM_PATCH   = '//dcwc/v1_1_14_12_Patch_A_Combat_Lua';
const STREAM_PARENT  = '//dcwc/v1_1_14_Parent_Combat_Lua';
const STREAM_TRUNK   = '//dcwc/combat_lua';
const STREAM_STAGING = '//dcwc/Gear_Character_Staging_Combat_Lua';

const CL_DESCRIPTION = 'Merging ';

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

function createCL(from, to) {
    const cmd = `p4 --field "Description=${CL_DESCRIPTION} ${from} to ${to}" change -o | p4 -c ${MY_WORKSPACE} change -i`;
    const output = runP4Command(cmd, WORKSPACE_PATH);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        return match ? match[1] : null;
    }
    return null;
}

function integrateStream(sourceStream, targetStream) {
    console.warn(`\n>>> 🔗 INTEGRATING: ${sourceStream} ➔ ${targetStream}`);

    // 1. Chuyển Workspace sang Stream đích
    console.log(`   Switching workspace to: ${targetStream}`);
    runP4Command(`p4 client -s -S ${targetStream}`, WORKSPACE_PATH);

    // 2. GET LATEST (Sync) - Cập nhật code mới nhất cho branch đích
    console.log(`   Syncing target workspace to latest...`);
    runP4Command(`p4 sync`, WORKSPACE_PATH); // Tương đương p4 sync //...

    // 3. Tạo Changelist
    const clId = createCL(sourceStream, targetStream);
    if (!clId) return;

    // 4. Chạy lệnh Integrate với cờ -i
    console.log(`   Running p4 integrate -i...`);
    const intCmd = `p4 integrate -c ${clId} -i "${sourceStream}/..." "${targetStream}/..."`;
    const result = runP4Command(intCmd, WORKSPACE_PATH);

    if (result && !result.includes("all revision(s) already integrated")) {
        console.log(`   ℹ️ Files opened in CL: ${clId}`);
        
        // 5. Resolve
        console.log(`   Resolving files (Auto-Safe)...`);
        runP4Command(`p4 resolve -c ${clId} -am -dw`, WORKSPACE_PATH);
        
        console.log(`   ✨ Hoàn tất integrate vào ${targetStream}.`);
    } else {
        console.log(`   ✅ Không có thay đổi nào cần integrate hoặc đã up-to-date.`);
        runP4Command(`p4 change -d ${clId}`, WORKSPACE_PATH);
    }
}

// ================= MAIN LOGIC =================

function main() {
    console.log("=== BẮT ĐẦU QUY TRÌNH INTEGRATE & SYNC LIÊN HOÀN ===");

    // Bước 1: Patch -> Parent
    integrateStream(STREAM_PATCH, STREAM_PARENT);

    // Bước 2: Parent -> Trunk
    integrateStream(STREAM_PARENT, STREAM_TRUNK);

    // Bước 3: Trunk -> Staging
    integrateStream(STREAM_TRUNK, STREAM_STAGING);

    console.log("\n=== HOÀN THÀNH ===");
    console.log("Mời bạn kiểm tra các Changelist trong P4V trước khi Submit.");
}

main();
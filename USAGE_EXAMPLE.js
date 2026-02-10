/**
 * USAGE GUIDE: ChangeList Validator
 * 
 * This module provides functions to validate Perforce changelists and handle review CLs.
 */

const {
    isValidChangelist,
    isReviewChangelist,
    validateAndResolveChangelist,
    validateChangelistArray
} = require('./changelistValidator');

// Example 1: Check if a single changelist is valid
console.log("\n=== Example 1: Validate a Single Changelist ===");
const workspace = 'C:/Users/hoang/Perforce/Company_Windows_Config';
const clNumber = '12345';

const result = validateAndResolveChangelist(clNumber, workspace);
console.log("Result:", result);
// Output example:
// {
//   cl: '12345',
//   isReview: false,
//   actualCl: null,
//   warning: null
// }

// Example 2: Handle a review changelist
console.log("\n=== Example 2: Handle Review Changelist ===");
const reviewCl = '98765';
const reviewResult = validateAndResolveChangelist(reviewCl, workspace);
console.log("Review CL Result:", reviewResult);
// Output example:
// {
//   cl: '98765',
//   isReview: true,
//   actualCl: '98766',
//   warning: 'Changelist 98765 is a review CL. Using actual CL 98766 instead.'
// }

// Example 3: Validate an array of changelists
console.log("\n=== Example 3: Validate Multiple Changelists ===");
const changelistArray = ['12345', '98765', '54321', '99999'];
const arrayResult = validateChangelistArray(changelistArray, workspace);

console.log("Valid CLs:", arrayResult.validCls);
console.log("Warnings:", arrayResult.warnings);
// Output example:
// Valid CLs: [ '12345', '54321', '98766' ]
// Warnings: [
//   'Changelist 98765 is a review CL. Using actual CL 98766 instead.',
//   'Changelist 99999 does not exist in the system'
// ]

// Example 4: Using in your existing code
console.log("\n=== Example 4: Integration into getFilePathByChangelist.js ===");
console.log(`
// In getFilePathByChangelist.js:

const { validateChangelistArray } = require('./changelistValidator');

function getChangelistNumbers(filePath) {
    if (!fs.existsSync(filePath)) {
        console.error(\`[ERROR] File not found: \${filePath}\`);
        return [];
    }
    
    const content = fs.readFileSync(filePath, 'utf8');
    const cls = content.split('\\n')
        .map(line => line.trim())
        .filter(line => line.length > 0 && !isNaN(line));
    const uniqueCls = [...new Set(cls)];
    
    // Validate all CLs and resolve review CLs
    console.log(\`--- Validating \${uniqueCls.length} changelists from file... ---\`);
    const { validCls, warnings } = validateChangelistArray(uniqueCls, CONFIG_SOURCE_WORKSPACE);
    
    // Log all warnings (review CLs, invalid CLs, etc.)
    warnings.forEach(warning => {
        console.warn(warning);
    });
    
    return validCls;
}
`);

console.log("\n=== How It Works ===");
console.log(`
1. User provides changelists in changelists.txt
2. getChangelistNumbers() reads the file
3. validateChangelistArray() processes each CL:
   - Checks if it's valid (exists in Perforce)
   - Detects if it's a review CL (pending with shelved files)
   - Finds the actual submitted CL if it's a review
   - Logs warnings for user visibility
4. Returns only valid, actual CLs (deduplicated and sorted)
5. User sees warning messages like:
   "[WARNING] Changelist 12345 is a review CL. Using actual CL 12346 instead."
`);

console.log("\n=== What Gets Logged ===");
console.log(`
Review CL Warning:
  [WARNING] Changelist 12345 is a review CL. Using actual CL 12346 instead.

Invalid CL Warning:
  [WARNING] Changelist 99999 does not exist in the system

No Warning (Normal CL):
  (nothing logged, CL used as-is)
`);

const { execSync } = require('child_process');

const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m",
    green: "\x1b[32m"
};

/**
 * Run a P4 command and return output
 * @param {string} command - P4 command to execute
 * @param {string} cwd - Working directory
 * @returns {string|null} Command output or null if failed
 */
function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 100 
        });
        return output.trim();
    } catch (error) {
        return null;
    }
}

/**
 * Check if a changelist is valid (exists in the system)
 * @param {string|number} clNumber - Changelist number to validate
 * @param {string} workspace - Workspace path for P4 command
 * @returns {boolean} True if changelist exists and is not a shelved/pending review
 */
function isValidChangelist(clNumber, workspace) {
    const cmd = `p4 describe -s ${clNumber}`;
    const output = runP4Command(cmd, workspace);

    // console.log(`===output clNumber: ${clNumber}, output: ${output}, include: ${output.includes(`*pending*`)}`)
    
    if (!output) {
        return false;
    }
    
    // Check if the changelist is found
    return !output.includes(`*pending*`);
}

/**
 * Check if a changelist is a review changelist (shelved files waiting for review)
 * @param {string|number} clNumber - Changelist number to check
 * @param {string} workspace - Workspace path for P4 command
 * @returns {boolean} True if this is a review changelist
 */
function isReviewChangelist(clNumber, workspace) {
    const cmd = `p4 describe -s ${clNumber}`;
    const output = runP4Command(cmd, workspace);
    
    if (!output) {
        return false;
    }
    
    // Review changelists typically have shelved files and status "pending"
    // Check for indicators of a review CL
    const hasDescription = output.includes('Shelved files:') || 
                          output.includes('pending') ||
                          output.match(/^Change \d+ by .* pending/m);
    
    return hasDescription;
}

/**
 * Extract the actual changelist number from a review changelist
 * In Perforce, when you submit a review, it creates a new CL with files integrated from the review CL
 * This function finds the submitted changelist that corresponds to a review CL
 * @param {string|number} reviewClNumber - Review changelist number
 * @param {string} workspace - Workspace path for P4 command
 * @returns {string|null} The actual submitted changelist number, or null if not found
 */
function getActualChangelistFromReview(reviewClNumber, workspace) {
    // Strategy: Look for the changelist that has integrated files from the review CL
    // We'll check the most recent changelists submitted after the review CL
    
    const cmd = `p4 changes -m 100`;
    const output = runP4Command(cmd, workspace);
    
    if (!output) {
        return null;
    }
    
    const lines = output.split('\n');
    
    // Find submitted changelists that might be related
    for (const line of lines) {
        const match = line.match(/^Change (\d+)/);
        if (match) {
            const candidateCl = match[1];
            
            // Check if this CL has files from the review CL
            const descCmd = `p4 describe -s ${candidateCl}`;
            const descOutput = runP4Command(descCmd, workspace);
            
            if (descOutput && descOutput.includes(`from ${reviewClNumber}`) || 
                descOutput.includes(`review ${reviewClNumber}`)) {
                return candidateCl;
            }
        }
    }
    
    return null;
}

/**
 * Get the original changelist information from a review CL
 * Alternative approach: read the description to find reference to original CL
 * @param {string|number} reviewClNumber - Review changelist number
 * @param {string} workspace - Workspace path for P4 command
 * @returns {string|null} The referenced changelist number, or null if not found
 */
function findReferencedChangelistInDescription(reviewClNumber, workspace) {
    const cmd = `p4 describe ${reviewClNumber}`;
    const output = runP4Command(cmd, workspace);
    
    if (!output) {
        return null;
    }
    
    // Look for CL references in description (e.g., "CL: 12345", "Changelist: 12345", etc.)
    const patterns = [
        /CL[:\s]+(\d+)/gi,
        /Changelist[:\s]+(\d+)/gi,
        /from[:\s]+(\d+)/gi,
        /related to[:\s]+(\d+)/gi
    ];
    
    for (const pattern of patterns) {
        const match = output.match(pattern);
        if (match) {
            const clNumber = match[1];
            // Verify this CL exists
            if (isValidChangelist(clNumber, workspace)) {
                return clNumber;
            }
        }
    }
    
    return null;
}

/**
 * Process a changelist number and return the actual changelist to use
 * If it's a review CL, find and return the actual submitted CL
 * If it's a normal CL, return it as-is
 * @param {string|number} clNumber - Changelist number from input
 * @param {string} workspace - Workspace path for P4 command
 * @returns {{cl: string, isReview: boolean, actualCl: string|null, warning: string|null}}
 */
function validateAndResolveChangelist(clNumber, workspace) {
    const result = {
        cl: String(clNumber),
        isReview: false,
        actualCl: null,
        warning: null
    };
    
    // Check if changelist exists
    if (!isValidChangelist(clNumber, workspace)) {
        result.warning = `Changelist ${clNumber} does not exist in the system`;
        return result;
    }
    
    // Check if it's a review changelist
    if (isReviewChangelist(clNumber, workspace)) {
        result.isReview = true;
        
        // Try to find the actual changelist
        let actualCl = getActualChangelistFromReview(clNumber, workspace);
        
        if (!actualCl) {
            actualCl = findReferencedChangelistInDescription(clNumber, workspace);
        }
        
        if (actualCl) {
            result.actualCl = actualCl;
            result.warning = `Changelist ${clNumber} is a review CL. Using actual CL ${actualCl} instead.`;
        } else {
            result.warning = `Changelist ${clNumber} appears to be a review CL, but could not find the associated submitted changelist.`;
        }
    }
    
    return result;
}

/**
 * Process an array of changelist numbers and resolve any review CLs
 * @param {array} clArray - Array of changelist numbers
 * @param {string} workspace - Workspace path for P4 command
 * @returns {{validCls: array, warnings: array}}
 */
function validateChangelistArray(clArray, workspace) {
    const validCls = [];
    const warnings = [];
    const seenCls = new Set();
    
    clArray.forEach(cl => {
        const result = validateAndResolveChangelist(cl, workspace);
        
        if (result.warning) {
            warnings.push(result.warning);
        }
        
        // Use actual CL if available, otherwise use the original
        const clToUse = result.actualCl || result.cl;
        
        // Avoid duplicates
        if (!seenCls.has(clToUse)) {
            seenCls.add(clToUse);
            validCls.push(clToUse);
        }
    });
    
    return {
        validCls: validCls.sort((a, b) => Number(a) - Number(b)),
        warnings: warnings
    };
}

module.exports = {
    isValidChangelist,
    isReviewChangelist,
    getActualChangelistFromReview,
    findReferencedChangelistInDescription,
    validateAndResolveChangelist,
    validateChangelistArray,
    runP4Command
};

import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
const stableSerialize = (value) => {
    if (value === null || value === undefined) {
        return "null";
    }
    if (typeof value !== "object") {
        return JSON.stringify(value);
    }
    if (Array.isArray(value)) {
        return `[${value.map((entry) => stableSerialize(entry)).join(",")}]`;
    }
    const record = value;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${stableSerialize(record[key])}`).join(",")}}`;
};
export const computeProfileTemplateBundleChecksum = (bundle) => {
    const payload = {
        bundleId: bundle.bundleId,
        version: bundle.version,
        description: bundle.description,
        owner: bundle.owner,
        createdAt: bundle.createdAt,
        updatedAt: bundle.updatedAt,
        entries: bundle.entries,
        starterPack: bundle.starterPack,
        exceptionPolicy: bundle.exceptionPolicy,
    };
    return `sha256:${crypto.createHash("sha256").update(stableSerialize(payload)).digest("hex")}`;
};
export const validateProfileTemplateBundle = (bundle) => {
    if (!bundle.bundleId.trim()) {
        throw new Error("Template bundle id is required");
    }
    if (!bundle.version.trim()) {
        throw new Error("Template bundle version is required");
    }
    if (!bundle.description.trim()) {
        throw new Error("Template bundle description is required");
    }
    if (!bundle.owner.trim()) {
        throw new Error("Template bundle owner is required");
    }
    if (!Number.isFinite(bundle.createdAt) || !Number.isFinite(bundle.updatedAt)) {
        throw new Error("Template bundle timestamps must be numeric epoch milliseconds");
    }
    if (!Array.isArray(bundle.entries) || bundle.entries.length === 0) {
        throw new Error("Template bundle must include at least one entry");
    }
    const seenKeys = new Set();
    for (const entry of bundle.entries) {
        if (!entry.key.trim()) {
            throw new Error("Template bundle entries must include a setting key");
        }
        const compositeKey = `${entry.level}:${entry.key}`;
        if (seenKeys.has(compositeKey)) {
            throw new Error(`Duplicate template bundle entry detected for ${entry.level}:${entry.key}`);
        }
        seenKeys.add(compositeKey);
    }
    if (!bundle.starterPack ||
        !Array.isArray(bundle.starterPack.docs) ||
        !Array.isArray(bundle.starterPack.ciChecks) ||
        !Array.isArray(bundle.starterPack.ssotLinks)) {
        throw new Error("Template bundle starter pack must provide docs, ciChecks, and ssotLinks arrays");
    }
    if (!bundle.exceptionPolicy || !bundle.exceptionPolicy.policyReference.trim() || !bundle.exceptionPolicy.exceptionIssuePrefix.trim()) {
        throw new Error("Template bundle exception policy must be defined");
    }
    return bundle;
};
export const loadProfileTemplateBundle = async (bundlePath) => {
    const content = await fs.promises.readFile(bundlePath, "utf-8");
    return validateProfileTemplateBundle(JSON.parse(content));
};
export const createProfileTemplateBundleManifest = (bundle, correlationId, appliedAt = Date.now()) => ({
    bundleId: bundle.bundleId,
    bundleVersion: bundle.version,
    bundleChecksum: computeProfileTemplateBundleChecksum(bundle),
    appliedAt,
    correlationId,
    starterPack: bundle.starterPack,
    exceptionPolicy: bundle.exceptionPolicy,
    entryCount: bundle.entries.length,
});
export const getTemplateBundleFilePath = (bundleDirectory, bundleId) => {
    return path.join(bundleDirectory, `${bundleId}.json`);
};
//# sourceMappingURL=template-bundles.js.map
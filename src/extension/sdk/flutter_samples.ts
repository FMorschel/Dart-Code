import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vs from "vscode";
import { FlutterCapabilities } from "../../shared/capabilities/flutter";
import { dartCodeExtensionIdentifier, FLUTTER_CREATE_PROJECT_TRIGGER_FILE } from "../../shared/constants";
import { getRandomInt } from "../../shared/utils/fs";
import * as util from "../utils";

export function createFlutterSampleInTempFolder(flutterCapabilities: FlutterCapabilities, sampleID: string): vs.Uri | undefined {
	// Ensure we're on at least Flutter v1 so we know creating samples works.
	if (!flutterCapabilities.supportsCreatingSamples) {
		vs.window.showErrorMessage("Opening sample projects requires Flutter v1.0 or later");
		return;
	}

	// Create a temp folder for the sample.
	const tempSamplePath = path.join(os.tmpdir(), dartCodeExtensionIdentifier, "flutter", "sample", sampleID, getRandomInt(0x1000, 0x10000).toString(16));

	// Create the empty folder so we can open it.
	util.mkDirRecursive(tempSamplePath);

	// Create a temp dart file to force extension to load when we open this folder.
	fs.writeFileSync(path.join(tempSamplePath, FLUTTER_CREATE_PROJECT_TRIGGER_FILE), sampleID);

	const hasFoldersOpen = !!(vs.workspace.workspaceFolders && vs.workspace.workspaceFolders.length);
	const openInNewWindow = hasFoldersOpen;
	const folderUri = vs.Uri.file(tempSamplePath);
	vs.commands.executeCommand("vscode.openFolder", folderUri, openInNewWindow);

	return folderUri;
}
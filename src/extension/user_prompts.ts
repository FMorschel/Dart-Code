import * as fs from "fs";
import * as path from "path";
import { Context } from "vm";
import * as vs from "vscode";
import { DART_STAGEHAND_PROJECT_TRIGGER_FILE, flutterExtensionIdentifier, FLUTTER_CREATE_PROJECT_TRIGGER_FILE, FLUTTER_STAGEHAND_PROJECT_TRIGGER_FILE, installFlutterExtensionPromptKey, userPromptContextPrefix } from "../shared/constants";
import { LogCategory, LogSeverity } from "../shared/enums";
import { StagehandTemplate } from "../shared/interfaces";
import { showFlutter2019Q2SurveyNotificationIfAppropriate } from "../shared/vscode/user_prompts";
import { fsPath, openInBrowser } from "../shared/vscode/utils";
import { WorkspaceContext } from "../shared/workspace";
import { markProjectCreationEnded, markProjectCreationStarted } from "./commands/sdk";
import { extensionVersion, getDartWorkspaceFolders, hasFlutterExtension, isDevExtension, reloadExtension } from "./utils";
import { log, logWarn } from "./utils/log";

export function showUserPrompts(context: Context, workspaceContext: WorkspaceContext): void {
	handleNewProjects(context);

	function shouldSuppress(key: string): boolean {
		const stateKey = `${userPromptContextPrefix}${key}`;
		return context.get(stateKey) === true;
	}

	/// Shows a prompt and stores the return value. Prompt should return `true` to mark
	/// this extension as seen-forever and it won't be shown again. Returning anything
	/// else will allow the prompt to appear again next time.
	function showPrompt(key: string, prompt: () => Thenable<boolean>): void {
		const stateKey = `${userPromptContextPrefix}${key}`;
		prompt().then((res) => context.update(stateKey, res), error);
	}

	if (workspaceContext.hasAnyFlutterProjects && !hasFlutterExtension && !shouldSuppress(installFlutterExtensionPromptKey))
		return showPrompt(installFlutterExtensionPromptKey, promptToInstallFlutterExtension);

	const lastSeenVersionNotification = context.lastSeenVersion;
	if (!lastSeenVersionNotification) {
		// If we've not got a stored version, this is the first install, so just
		// stash the current version and don't show anything.
		context.lastSeenVersion = extensionVersion;
	} else if (!isDevExtension && lastSeenVersionNotification !== extensionVersion) {
		const versionLink = extensionVersion.split(".").slice(0, 2).join(".").replace(".", "-");
		promptToShowReleaseNotes(extensionVersion, versionLink).then(() =>
			context.lastSeenVersion = extensionVersion,
		);
		return;
	}

	if (workspaceContext.hasAnyFlutterProjects) {
		if (showFlutter2019Q2SurveyNotificationIfAppropriate(context, Date.now(), logWarn))
			return; // Bail if we showed it, so we won't show any other notifications.
	}

	// (though, there are no other notifications right now...)
}

async function promptToInstallFlutterExtension(): Promise<boolean> {
	const installExtension = "Install Flutter Extension";
	const res = await vs.window.showInformationMessage(
		"The Flutter extension is required to work with Flutter projects.",
		installExtension,
	);
	if (res === installExtension) {
		await vs.window.withProgress({ location: vs.ProgressLocation.Notification },
			(progress) => {
				progress.report({ message: "Installing Flutter extension" });

				return new Promise((resolve) => {
					vs.extensions.onDidChange((e) => resolve());
					vs.commands.executeCommand("workbench.extensions.installExtension", flutterExtensionIdentifier);
				});
			},
		);
		reloadExtension();
	}

	return false;
}

async function promptToShowReleaseNotes(versionDisplay: string, versionLink: string): Promise<boolean> {
	const res = await vs.window.showInformationMessage(
		`Dart Code has been updated to v${versionDisplay}`,
		`Show Release Notes`,
	);
	if (res) {
		openInBrowser(`https://dartcode.org/releases/v${versionLink}/`);
	}
	return true; // Always mark this as done; we don't want to prompt the user multiple times.
}

function error(err: any) {
	vs.window.showErrorMessage(err.message);
}

function handleNewProjects(context: Context) {
	getDartWorkspaceFolders().forEach((wf) => {
		handleStagehandTrigger(wf, DART_STAGEHAND_PROJECT_TRIGGER_FILE);
		handleStagehandTrigger(wf, FLUTTER_STAGEHAND_PROJECT_TRIGGER_FILE);
		handleFlutterCreateTrigger(wf);
	});
}

async function handleStagehandTrigger(wf: vs.WorkspaceFolder, triggerFilename: string): Promise<void> {
	const triggerFile = path.join(fsPath(wf.uri), triggerFilename);
	if (fs.existsSync(triggerFile)) {
		const templateJson = fs.readFileSync(triggerFile).toString().trim();
		let template: StagehandTemplate;
		try {
			template = JSON.parse(templateJson);
		} catch (e) {
			vs.window.showErrorMessage("Failed to run Stagehand to create project");
			return;
		}
		fs.unlinkSync(triggerFile);
		log(`Creating Dart project for ${fsPath(wf.uri)}`, LogSeverity.Info, LogCategory.CommandProcesses);
		try {
			markProjectCreationStarted();

			const success = await createDartProject(fsPath(wf.uri), template.name);
			if (success) {
				log(`Fetching packages for newly-created project`, LogSeverity.Info, LogCategory.CommandProcesses);
				await vs.commands.executeCommand("dart.getPackages", wf.uri);
				handleDartWelcome(wf, template);
				log(`Finished creating new project!`, LogSeverity.Info, LogCategory.CommandProcesses);
			} else {
				log(`Failed to create new project`, LogSeverity.Info, LogCategory.CommandProcesses);
			}
		} finally {
			markProjectCreationEnded();
		}
	}
}

async function handleFlutterCreateTrigger(wf: vs.WorkspaceFolder): Promise<void> {
	const flutterTriggerFile = path.join(fsPath(wf.uri), FLUTTER_CREATE_PROJECT_TRIGGER_FILE);
	if (fs.existsSync(flutterTriggerFile)) {
		let sampleID: string | undefined = fs.readFileSync(flutterTriggerFile).toString().trim();
		sampleID = sampleID ? sampleID : undefined;
		fs.unlinkSync(flutterTriggerFile);
		try {
			markProjectCreationStarted();
			const success = await createFlutterProject(fsPath(wf.uri), sampleID);
			if (success)
				handleFlutterWelcome(wf, sampleID);
		} finally {
			markProjectCreationEnded();
		}
	}
}

async function createDartProject(projectPath: string, templateName: string): Promise<boolean> {
	const code = await vs.commands.executeCommand("_dart.create", projectPath, templateName) as number;
	return code === 0;
}

async function createFlutterProject(projectPath: string, sampleID: string | undefined): Promise<boolean> {
	const projectName = sampleID ? "sample" : undefined;
	const code = await vs.commands.executeCommand("_flutter.create", projectPath, projectName, sampleID) as number;
	return code === 0;
}

function handleFlutterWelcome(workspaceFolder: vs.WorkspaceFolder, sampleID: string | undefined) {
	const entryFile = path.join(fsPath(workspaceFolder.uri), "lib/main.dart");
	openFile(entryFile);
	if (sampleID)
		vs.window.showInformationMessage(`${sampleID} sample ready! Connect a device and press F5 to run.`);
	else
		vs.window.showInformationMessage("Your Flutter project is ready! Connect a device and press F5 to start running.");
}

function handleDartWelcome(workspaceFolder: vs.WorkspaceFolder, template: StagehandTemplate) {
	const workspacePath = fsPath(workspaceFolder.uri);
	const projectName = path.basename(workspacePath);
	const entryFile = path.join(workspacePath, template.entrypoint.replace("__projectName__", projectName));
	openFile(entryFile);
	vs.window.showInformationMessage(`${template.label} project ready!`);
}

/// Opens a file, but does it in a setTimeout to work around VS Code reveal bug
/// https://github.com/Microsoft/vscode/issues/71588#event-2252962973
function openFile(entryFile: string) {
	if (!fs.existsSync(entryFile))
		return;

	// TODO: Remove this setTimeout when it's no longer required.
	setTimeout(() => {
		vs.commands.executeCommand("vscode.open", vs.Uri.file(entryFile));
	}, 100);
}
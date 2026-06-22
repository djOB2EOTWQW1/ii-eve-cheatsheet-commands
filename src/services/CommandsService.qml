pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// Bundled so the extension is self-contained on shells (ii-vynx) that lack this service.
// The data file matches ii-eve's Directories.commandsPath so commands are shared there.
Singleton {
    id: root

    property ListModel commandsModel: ListModel {}
    property bool importing: false
    property var tagCounts: ({})
    // Bumped on every mutation so delegate bindings that snapshot via
    // commandsModel.get(idx) re-evaluate (those bindings otherwise can't tell
    // when rows shift, since their idx dependency hasn't changed).
    property int modelVersion: 0

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/commands.json`)

    function save() {
        const arr = [];
        for (let i = 0; i < commandsModel.count; i++) {
            const item = commandsModel.get(i);
            const tags = [];
            for (let t = 0; t < item.tags.count; t++) {
                tags.push(item.tags.get(t).modelData);
            }
            arr.push({
                id: item.id,
                command: item.command,
                description: item.description,
                tags
            });
        }
        fileView.setText(JSON.stringify(arr, null, 2));
        updateTagCounts();
    }

    function updateTagCounts() {
        const counts = {};
        let total = 0;
        for (let i = 0; i < commandsModel.count; i++) {
            total++;
            const item = commandsModel.get(i);
            if (!item || !item.tags) continue;
            for (let t = 0; t < item.tags.count; t++) {
                const tag = item.tags.get(t).modelData;
                counts[tag] = (counts[tag] || 0) + 1;
            }
        }
        counts[""] = total;
        tagCounts = counts;
    }

    function addCommand(command, description, tags) {
        const id = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);
        const tagList = tags.map(t => ({ modelData: t }));
        commandsModel.append({ id, command, description, tags: tagList });
        modelVersion++;
        save();
    }

    function updateCommand(id, command, description, tags) {
        for (let i = 0; i < commandsModel.count; i++) {
            if (commandsModel.get(i).id === id) {
                const tagList = tags.map(t => ({ modelData: t }));
                commandsModel.set(i, { id, command, description, tags: tagList });
                modelVersion++;
                save();
                return;
            }
        }
    }

    function deleteCommand(id) {
        for (let i = 0; i < commandsModel.count; i++) {
            if (commandsModel.get(i).id === id) {
                commandsModel.remove(i);
                modelVersion++;
                save();
                return;
            }
        }
    }

    function clearAll() {
        if (commandsModel.count === 0) return;
        commandsModel.clear();
        modelVersion++;
        save();
    }

    // Returns array of unique tag strings across all commands
    function allTags() {
        const set = new Set();
        for (let i = 0; i < commandsModel.count; i++) {
            const item = commandsModel.get(i);
            if (!item || !item.tags || item.tags.count === undefined) continue;
            for (let t = 0; t < item.tags.count; t++) {
                const tagObj = item.tags.get(t);
                if (tagObj && tagObj.modelData) {
                    set.add(tagObj.modelData);
                }
            }
        }
        return Array.from(set).sort();
    }

    signal importFinished(bool success, string errorMsg)

    function importCommands(path) {
        root.importing = true;
        const plainPath = FileUtils.trimFileProtocol(path);
        importFileView.path = Qt.resolvedUrl("file://" + plainPath);
        importFileView.reload();
    }

    FileView {
        id: importFileView
        path: ""
        onLoaded: {
            const text = importFileView.text();
            if (!text) {
                importFinished(false, "File is empty.");
                return;
            }
            try {
                const data = JSON.parse(text);
                if (!Array.isArray(data)) {
                    importFinished(false, "Invalid format: Expected an array of commands.");
                    return;
                }
                const batch = data.map(item => {
                    const id = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);
                    const tagList = (item.tags || []).map(t => ({ modelData: t }));
                    return {
                        id: id,
                        command: item.command || "",
                        description: item.description || "",
                        tags: tagList
                    };
                });
                commandsModel.append(batch);
                root.importing = false;
                modelVersion++;
                save();
                importFinished(true, "");
            } catch (e) {
                root.importing = false;
                importFinished(false, "Failed to parse JSON: " + e.message);
            }
        }
        onLoadFailed: (error) => {
            root.importing = false;
            importFinished(false, "Could not read file (error " + error + ").");
        }
    }

    FileView {
        id: fileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                const data = JSON.parse(fileView.text());
                if (!Array.isArray(data)) {
                    console.log("[CommandsService] Ignoring non-array commands file.");
                    return;
                }
                const batch = data.map(item => {
                    const tagList = (item.tags || []).map(t => ({ modelData: t }));
                    return {
                        id: item.id || Date.now().toString(36),
                        command: item.command || "",
                        description: item.description || "",
                        tags: tagList
                    };
                });
                commandsModel.clear();
                commandsModel.append(batch);
                modelVersion++;
                updateTagCounts();
            } catch (e) {
                console.log("[CommandsService] Error loading: " + e);
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[CommandsService] File not found, creating new file.");
                fileView.setText("[]");
            } else {
                console.log("[CommandsService] Load error: " + error);
            }
        }
    }

    Component.onCompleted: fileView.reload()
}

pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property bool bypassPermissions: Persistent.states?.ai?.bypassPermissions ?? false
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function setBypassPermissions(value: bool) {
        Persistent.states.ai.bypassPermissions = value;
        root.bypassPermissions = value;
        root.addMessage(value ? Translation.tr("⚠️ **Permission Bypass ENABLED**: Commands will execute automatically without confirmation.") : Translation.tr("🛡️ **Permission Bypass DISABLED**: Commands require manual approval."), root.interfaceRole);
    }

    function toggleBypassPermissions() {
        setBypassPermissions(!root.bypassPermissions);
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "update",
                    "description": "Update working notes before tool execution",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "previous_step": {
                                "type": "string",
                                "description": "Summary of previous step completed"
                            },
                            "plan": {
                                "type": "string",
                                "description": "Current overall plan"
                            },
                            "next_step": {
                                "type": "string",
                                "description": "Next step to execute"
                            }
                        },
                        "required": ["previous_step", "plan", "next_step"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format])
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
	    // - key_get_link: Link to get an API key
	    // - key_get_description: Description of pricing and how to get an API key
	    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
	    // - omit_temperature: Whether to let the provider use its default sampling parameters.
	    // - thinkingLevel: Gemini thinking level. Supported values depend on the selected model.
	    // - includeReasoningInHistory: Send saved reasoning_content back to OpenAI-compatible APIs that require it.
	    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
	    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-3.8-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3.8 Flash (High)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's hybrid reasoning Flash model (High thinking effort)\nPro-level reasoning intelligence at Flash speeds with search grounding, function calling, and deep chain-of-thought."),
            "homepage": "https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
            "model": "gemini-3.8-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: paid/free-tier availability depends on your Gemini API account.\n\n**Instructions**: Log into Google AI Studio, create an API key, then set it here with `/key`."),
            "api_format": "gemini",
            "omit_temperature": true,
            "thinkingLevel": "high",
            "includeThoughts": true,
        }),
        "gemini-3.8-flash-medium": aiModelComponent.createObject(this, {
            "name": "Gemini 3.8 Flash (Medium)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's hybrid reasoning Flash model (Medium thinking effort)\nOptimal balance for general video Q&A, lecture summarization, and clip retrieval."),
            "homepage": "https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
            "model": "gemini-3.8-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: paid/free-tier availability depends on your Gemini API account.\n\n**Instructions**: Log into Google AI Studio, create an API key, then set it here with `/key`."),
            "api_format": "gemini",
            "omit_temperature": true,
            "thinkingLevel": "medium",
            "includeThoughts": true,
        }),
        "gemini-3.8-flash-low": aiModelComponent.createObject(this, {
            "name": "Gemini 3.8 Flash (Low)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's hybrid reasoning Flash model (Low thinking effort)\nFast responses with lightweight reasoning for simple queries and transcript searches."),
            "homepage": "https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
            "model": "gemini-3.8-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: paid/free-tier availability depends on your Gemini API account.\n\n**Instructions**: Log into Google AI Studio, create an API key, then set it here with `/key`."),
            "api_format": "gemini",
            "omit_temperature": true,
            "thinkingLevel": "low",
            "includeThoughts": true,
        }),
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
	            "api_format": "gemini",
	        }),
	        "gemini-3.6-flash": aiModelComponent.createObject(this, {
	            "name": "Gemini 3.6 Flash",
	            "icon": "google-gemini-symbolic",
	            "description": Translation.tr("Online | Google's latest stable Flash model\nBest default for fast coding, agentic tasks, long context, Search grounding, URL context, structured outputs, and function calling."),
	            "homepage": "https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash",
	            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:streamGenerateContent?alt=sse",
	            "model": "gemini-3.6-flash",
	            "requires_key": true,
	            "key_id": "gemini",
	            "key_get_link": "https://aistudio.google.com/app/apikey",
	            "key_get_description": Translation.tr("**Pricing**: paid/free-tier availability depends on your Gemini API account.\n\n**Instructions**: Log into Google AI Studio, create an API key, then set it here with `/key`."),
	            "api_format": "gemini",
	            "omit_temperature": true,
	            "thinkingLevel": "medium",
	        }),
	        "gemini-3-flash": aiModelComponent.createObject(this, {
	            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at the speed and pricing of Flash."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
	            "requires_key": true,
	            "key_id": "gemini",
	            "key_get_link": "https://aistudio.google.com/app/apikey",
	            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
	            "api_format": "gemini",
	            "omit_temperature": true,
	            "thinkingLevel": "medium",
	        }),
	        "deepseek-v4-flash": aiModelComponent.createObject(this, {
	            "name": "DeepSeek V4 Flash",
	            "icon": "deepseek-symbolic",
	            "description": Translation.tr("Online | DeepSeek paid API | Very cheap 1M-context model in non-thinking mode for fast sidebar answers."),
	            "homepage": "https://api-docs.deepseek.com/quick_start/pricing",
	            "endpoint": "https://api.deepseek.com/chat/completions",
	            "model": "deepseek-v4-flash",
	            "requires_key": true,
	            "key_id": "deepseek",
	            "key_get_link": "https://platform.deepseek.com/api_keys",
	            "key_get_description": Translation.tr("**Pricing**: DeepSeek paid balance. V4 Flash is the cheap option.\n\n**Instructions**: Create a DeepSeek API key, then set it here with `/key`."),
	            "api_format": "openai",
	            "extraParams": {
	                "thinking": { "type": "disabled" },
	            },
	        }),
	        "deepseek-v4-flash-think": aiModelComponent.createObject(this, {
	            "name": "DeepSeek V4 Flash Think",
	            "icon": "deepseek-symbolic",
	            "description": Translation.tr("Online | DeepSeek paid API | Cheap thinking mode with streamed reasoning shown in the chat."),
	            "homepage": "https://api-docs.deepseek.com/guides/thinking_mode",
	            "endpoint": "https://api.deepseek.com/chat/completions",
	            "model": "deepseek-v4-flash",
	            "requires_key": true,
	            "key_id": "deepseek",
	            "key_get_link": "https://platform.deepseek.com/api_keys",
	            "key_get_description": Translation.tr("**Pricing**: DeepSeek paid balance. Thinking mode can use more output tokens.\n\n**Instructions**: Create a DeepSeek API key, then set it here with `/key`."),
	            "api_format": "openai",
	            "omit_temperature": true,
	            "includeReasoningInHistory": true,
	            "extraParams": {
	                "thinking": { "type": "enabled" },
	                "reasoning_effort": "high",
	            },
	        }),
	        "deepseek-v4-pro-think": aiModelComponent.createObject(this, {
	            "name": "DeepSeek V4 Pro Think",
	            "icon": "deepseek-symbolic",
	            "description": Translation.tr("Online | DeepSeek paid API | Higher quality thinking model when Flash is not enough."),
	            "homepage": "https://api-docs.deepseek.com/quick_start/pricing",
	            "endpoint": "https://api.deepseek.com/chat/completions",
	            "model": "deepseek-v4-pro",
	            "requires_key": true,
	            "key_id": "deepseek",
	            "key_get_link": "https://platform.deepseek.com/api_keys",
	            "key_get_description": Translation.tr("**Pricing**: DeepSeek paid balance. Pro costs more than Flash.\n\n**Instructions**: Create a DeepSeek API key, then set it here with `/key`."),
	            "api_format": "openai",
	            "omit_temperature": true,
	            "includeReasoningInHistory": true,
	            "extraParams": {
	                "thinking": { "type": "enabled" },
	                "reasoning_effort": "high",
	            },
	        }),
	        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            (Config?.options.ai?.extraModels ?? []).forEach(model => {
                const safeModelName = root.safeModelName(model["model"]);
                root.addModel(safeModelName, model)
            });
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string requestPayloadFilePath: "/tmp/quickshell/ai/request.json"
    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

	    function addModel(modelName, data) {
	        root.models[modelName] = aiModelComponent.createObject(this, data);
	        root.modelList = Object.keys(root.models);
	    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId] || models["gemini-3.8-flash"] || models[modelList[0]];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    FileView {
        id: requesterPayloadFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy
        property bool continuationQueued: false
        property string stderrOutput: ""

        function markDone() {
            if (!requester.message || requester.message.done) return;
            requester.message.done = true;
            if (!requester.continuationQueued && root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveChat("lastSession")
            root.responseFinished()
        }

        function queueContinuation() {
            if (requester.running) {
                requester.continuationQueued = true;
            } else {
                Qt.callLater(requester.makeRequest);
            }
        }

        function makeRequest() {
            if (requester.running) {
                requester.continuationQueued = true;
                return;
            }
            const model = models[currentModelId];

            // Fetch API keys if needed
            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state
            requester.stderrOutput = "";

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]).filter(m => !!m);
            // Filter out interface messages AND empty/failed assistant messages that have no content and no functionCall
            const filteredMessageArray = messageArray.filter(message => {
                if (message.role === Ai.interfaceRole) return false;
                if (message.role === "assistant" && !message.functionName && !message.functionCall && (!message.content || message.content.trim().length === 0) && (!message.rawContent || message.rawContent.trim().length === 0)) return false;
                return true;
            });
            if (filteredMessageArray.length === 0 || filteredMessageArray[filteredMessageArray.length - 1].role === "assistant") {
                console.error("[AI] Refusing request with no user/tool-result turn after the last assistant turn");
                root.addMessage(Translation.tr("Could not continue safely because the request history ends with an assistant turn."), root.interfaceRole);
                return;
            }
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePath);

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);

            /* Ensure temp directory exists with restricted user permissions */
            Quickshell.execDetached(["bash", "-c", "mkdir -p -m 700 /tmp/quickshell/ai && chmod 700 /tmp/quickshell/ai 2>/dev/null || true"]);

            /* Write payload to request.json to avoid command line length limits */
            const jsonPayload = JSON.stringify(data);
            const payloadPath = CF.FileUtils.trimFileProtocol(root.requestPayloadFilePath);
            requesterPayloadFile.path = Qt.resolvedUrl(payloadPath);
            requesterPayloadFile.setText(jsonPayload);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\nset -o pipefail\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string using --data-binary with the payload file */
            let scriptRequestContent = ""
            scriptRequestContent += `curl -s -S --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data-binary "@${payloadPath}"`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message && requester.message.thinking) requester.message.thinking = false;

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                requester.stderrOutput += data + "\n";
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (exitCode !== 0 && (!requester.message.content || requester.message.content.trim().length === 0)) {
                const errText = requester.stderrOutput.trim();
                const displayErr = errText.length > 0 
                    ? `⚠️ **Request failed (code ${exitCode})**:\n\`\`\`\n${errText}\n\`\`\``
                    : `⚠️ **Request failed (code ${exitCode})**: Connection lost or request was interrupted.`;
                requester.message.rawContent = displayErr;
                requester.message.content = displayErr;
            }

            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }

            if (requester.continuationQueued) {
                requester.continuationQueued = false;
                Qt.callLater(requester.makeRequest);
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

	    function createFunctionOutputMessage(name, output, includeOutputInChat = true, functionCall = null) {
	        return aiMessageComponent.createObject(root, {
	            "role": "user",
	            "content": output,
	            "rawContent": output,
	            "functionName": name,
	            "functionCall": functionCall ?? ({ name: name }),
	            "functionResponse": output,
	            "thinking": false,
	            "done": true,
	            "visibleToUser": false,
	        });
	    }

	    function addFunctionOutputMessage(name, output, functionCall = null) {
	        const aiMessage = createFunctionOutputMessage(name, output, true, functionCall);
	        const id = idForMessage(aiMessage);
	        root.messageIDs = [...root.messageIDs, id];
	        root.messageByID[id] = aiMessage;
    }

	    function rejectCommand(message: AiMessageData) {
	        if (!message.functionPending) return;
	        message.functionPending = false; // User decided, no more "thinking"
	        addFunctionOutputMessage(message.functionName, JSON.stringify({
	            "ok": false,
	            "error": {
	                "code": "USER_REJECTED",
	                "message": Translation.tr("Command rejected by user")
	            }
	        }), message.functionCall)
	        requester.queueContinuation();
	    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

	        const responseMessage = createFunctionOutputMessage(message.functionName, "", false, message.functionCall);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.output = "";
        commandExecutionProc.timedOut = false;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property string output: ""
        property bool timedOut: false
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["timeout", "--signal=TERM", "--kill-after=2s", "30s", "bash", "-c", shellCommand]

        function appendOutput(data) {
            if (commandExecutionProc.output.length < 131072) {
                commandExecutionProc.output += data;
            } else if (!commandExecutionProc.output.endsWith("[... Output truncated ...]\n")) {
                commandExecutionProc.output += "\n[... Output truncated ...]\n";
            }
            const displayOutput = commandExecutionProc.output.length > 16384 
                ? commandExecutionProc.output.slice(0, 8192) + "\n\n[... Truncated for display ...]\n\n" + commandExecutionProc.output.slice(-8192)
                : commandExecutionProc.output;
            const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${displayOutput}</tt>\n</think>`;
            commandExecutionProc.message.rawContent = updatedContent;
            commandExecutionProc.message.content = updatedContent;
        }

        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.appendOutput(output + "\n");
            }
        }
        stderr: SplitParser {
            onRead: (output) => commandExecutionProc.appendOutput(output + "\n")
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.timedOut = exitCode === 124 || exitCode === 137;
            let finalOutput = commandExecutionProc.output;
            if (finalOutput.length > 65536) {
                finalOutput = finalOutput.slice(0, 32768) + `\n\n[... Tool output truncated: total ${commandExecutionProc.output.length} characters ...]\n\n` + finalOutput.slice(-32768);
            }
            const result = {
                "ok": !commandExecutionProc.timedOut && exitCode === 0,
                "command": commandExecutionProc.shellCommand,
                "exitCode": exitCode,
                "exitStatus": String(exitStatus),
                "timedOut": commandExecutionProc.timedOut,
                "output": finalOutput
            };
            if (commandExecutionProc.timedOut) {
                result.error = {
                    "code": "TIMEOUT",
                    "message": "Command exceeded the 30 second tool timeout"
                };
            } else if (exitCode !== 0) {
                result.error = {
                    "code": "NON_ZERO_EXIT",
                    "message": `Command exited with code ${exitCode}`
                };
            }
            commandExecutionProc.message.functionResponse = JSON.stringify(result);
            commandExecutionProc.appendOutput(`[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`);
            requester.queueContinuation();
        }
    }

    function isDestructiveCommand(cmd) {
        if (!cmd || typeof cmd !== "string") return false;
        const lower = cmd.trim().toLowerCase();
        return /\b(sudo|rm|dd|mkfs|wipefs|fdisk|parted|reboot|shutdown|poweroff|kill|pkill|killall|mv)\b/.test(lower) || />\s*\/dev\//.test(lower);
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
	    try {
	        if (name === "update") {
	            let note = "";
	            if (args.plan) note += `**Plan**: ${args.plan}\n`;
	            if (args.next_step) note += `**Next Step**: ${args.next_step}\n`;
	            if (note.length > 0) {
	                message.rawContent += `\n\n<think>\n${note}</think>\n\n`;
	                message.content += `\n\n<think>\n${note}</think>\n\n`;
	            }
	            addFunctionOutputMessage(name, JSON.stringify({ "ok": true, "status": "acknowledged" }), message.functionCall);
	            requester.queueContinuation();
	        } else if (name === "switch_to_search_mode") {
	            const modelId = root.currentModelId;
	            root.currentTool = "search"
	            root.postResponseHook = () => { root.currentTool = "functions" }
	            addFunctionOutputMessage(name, JSON.stringify({ "ok": true, "message": Translation.tr("Switched to search mode. Continue with the user's request.") }), message.functionCall)
	            requester.queueContinuation();
	        } else if (name === "get_shell_config") {
	            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
	            addFunctionOutputMessage(name, JSON.stringify({ "ok": true, "config": configJson }), message.functionCall);
	            requester.queueContinuation();
	        } else if (name === "set_shell_config") {
	            if (!args.key || args.value === undefined || args.value === null) {
	                addFunctionOutputMessage(name, JSON.stringify({ "ok": false, "error": { "code": "INVALID_ARGUMENTS", "message": Translation.tr("Must provide `key` and `value`.") } }), message.functionCall);
	                requester.queueContinuation();
	                return;
	            }
	            const key = args.key;
	            const value = args.value;
	            Config.setNestedValue(key, value);
	            addFunctionOutputMessage(name, JSON.stringify({ "ok": true, "key": key, "value": value }), message.functionCall);
	            requester.queueContinuation();
	        } else if (name === "run_shell_command") {
		            if (!args.command || args.command.length === 0) {
		                addFunctionOutputMessage(name, JSON.stringify({ "ok": false, "error": { "code": "INVALID_ARGUMENTS", "message": Translation.tr("Must provide `command`.") } }), message.functionCall);
		                requester.queueContinuation();
		                return;
		            }
            const contentToAppend = `\n\n\`\`\`command\n${args.command}\n\`\`\`\n`;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            
            // Safety guard: Even if bypassPermissions is enabled, NEVER auto-run destructive commands!
            const dangerous = root.isDestructiveCommand(args.command);
            if (root.bypassPermissions && !dangerous) {
                message.functionPending = false;
                const responseMessage = createFunctionOutputMessage(name, "", false, message.functionCall);
                const id = idForMessage(responseMessage);
                root.messageIDs = [...root.messageIDs, id];
                root.messageByID[id] = responseMessage;

                commandExecutionProc.message = responseMessage;
                commandExecutionProc.baseMessageContent = responseMessage.content;
                commandExecutionProc.shellCommand = args.command;
                commandExecutionProc.output = "";
                commandExecutionProc.timedOut = false;
                commandExecutionProc.running = true;
            } else {
                message.functionPending = true; // Wait for manual approval
                if (root.bypassPermissions && dangerous) {
                    root.addMessage(Translation.tr("⚠️ **Destructive command detected**: Confirmation required even with bypass enabled."), root.interfaceRole);
                }
            }
        }
        else {
            addFunctionOutputMessage(name, JSON.stringify({ "ok": false, "error": { "code": "UNKNOWN_TOOL", "message": Translation.tr("Unknown function call: %1").arg(name) } }), message.functionCall);
            requester.queueContinuation();
        }
	    } catch (e) {
	        addFunctionOutputMessage(name, JSON.stringify({
	            "ok": false,
	            "error": {
	                "code": "TOOL_EXECUTION_ERROR",
	                "message": String(e)
	            }
	        }), message.functionCall);
	        requester.queueContinuation();
	    }
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
	                "annotations": message.annotations,
	                "annotationSources": message.annotationSources,
	                "providerParts": message.providerParts,
	                "reasoningContent": message.reasoningContent,
	                "responseContent": message.responseContent,
	                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "thoughtSignature": message.thoughtSignature || message.functionCall?.thoughtSignature || "",
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    readonly property bool hasLastSession: savedChats.some(f => f.endsWith("lastSession.json"))

    function resumeLastSession() {
        return root.loadChat("lastSession");
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    FileView {
        id: chatExportFile
        property string exportPath: ""
        path: exportPath
        blockLoading: true
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            if (!saveContent || saveContent.trim().length === 0) {
                root.addMessage(Translation.tr("No saved chat found named '%1'").arg(chatName), root.interfaceRole);
                return false;
            }
            const saveData = JSON.parse(saveContent)
            if (!Array.isArray(saveData) || saveData.length === 0) {
                root.addMessage(Translation.tr("Saved chat '%1' is empty").arg(chatName), root.interfaceRole);
                return false;
            }
            const validMessages = saveData.filter(message => {
                if (message.role === "assistant" && !message.functionName && !message.functionCall && (!message.content || message.content.trim().length === 0) && (!message.rawContent || message.rawContent.trim().length === 0)) {
                    return false;
                }
                return true;
            });
            root.clearMessages()
            root.messageIDs = validMessages.map((_, i) => {
                return i
            })
            for (let i = 0; i < validMessages.length; i++) {
                const message = validMessages[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "providerParts": message.providerParts,
                    "reasoningContent": message.reasoningContent,
                    "responseContent": message.responseContent,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "thoughtSignature": message.thoughtSignature || message.functionCall?.thoughtSignature || "",
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
            root.addMessage(Translation.tr("Loaded chat: **%1** (%2 messages)").arg(chatName).arg(validMessages.length), root.interfaceRole);
            return true;
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
            root.addMessage(Translation.tr("Failed to load chat '%1': %2").arg(chatName).arg(String(e)), root.interfaceRole);
            return false;
        } finally {
            getSavedChats.running = true;
        }
    }

    /**
     * Exports the active chat conversation to a clean Markdown file.
     * @param fileName Optional custom filename (defaults to ai-chat-<timestamp>.md)
     */
    function exportChatToMarkdown(fileName) {
        if (root.messageIDs.length === 0) {
            root.addMessage(Translation.tr("No active chat to export"), root.interfaceRole);
            return;
        }
        let cleanName = (fileName ?? "").trim();
        if (cleanName.length === 0) {
            const dateStr = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
            cleanName = `ai-chat-${dateStr}.md`;
        } else if (!cleanName.endsWith(".md")) {
            cleanName += ".md";
        }

        const exportDir = `${Directories.state}/user/ai/exports`;
        Quickshell.execDetached(["mkdir", "-p", exportDir]);
        const fullPath = `${exportDir}/${cleanName}`;

        let md = `# AI Chat Export\n\n- **Date**: ${new Date().toLocaleString()}\n- **Model**: ${root.getModel()?.name ?? "AI"}\n\n---\n\n`;
        for (let i = 0; i < root.messageIDs.length; i++) {
            const id = root.messageIDs[i];
            const msg = root.messageByID[id];
            if (!msg || msg.visibleToUser === false) continue;
            if (msg.role === "user") {
                md += `### 👤 User\n\n${msg.rawContent || msg.content}\n\n---\n\n`;
            } else if (msg.role === "assistant") {
                md += `### 🤖 Assistant (${msg.model || "AI"})\n\n${msg.rawContent || msg.content}\n\n---\n\n`;
            } else if (msg.role === root.interfaceRole) {
                md += `> ℹ️ *System: ${msg.rawContent || msg.content}*\n\n---\n\n`;
            }
        }

        chatExportFile.exportPath = fullPath;
        chatExportFile.setText(md);
        root.addMessage(Translation.tr("Chat exported to:\n`%1`").arg(fullPath), root.interfaceRole);
    }
}

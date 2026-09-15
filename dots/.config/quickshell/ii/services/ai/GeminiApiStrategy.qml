import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property string fileUriVarName: "file_uri"
    readonly property string fileMimeTypeVarName: "MIME_TYPE"
    readonly property string fileUriSubstitutionString: "{{ fileUriVarName }}"
    readonly property string fileMimeTypeSubstitutionString: "{{ fileMimeTypeVarName }}"
    property string buffer: ""
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        const separator = model.endpoint.includes("?") ? "&" : "?";
        const result = model.endpoint + `${separator}key=\$\{${root.apiKeyEnvVarName}\}`;
        return result;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let contents = [];

        for (let i = 0; i < messages.length; i++) {
            const message = messages[i];
            const geminiApiRoleName = (message.role === "assistant") ? "model" : message.role;

            // 1. Tool result message (user role responding to a previous functionCall)
            if (message.role === "user" && message.functionName && message.functionName.length > 0) {
                let responseContent = (message.functionResponse !== undefined && message.functionResponse !== null && message.functionResponse.length > 0)
                    ? message.functionResponse
                    : (message.content || message.rawContent || "");
                let responseObj = { "content": responseContent };
                const functionResponse = {
                    "name": message.functionName,
                    "response": responseObj
                };
                if (message.functionCall?.id) functionResponse.id = message.functionCall.id;
                contents.push({
                    "role": "user",
                    "parts": [{ functionResponse: functionResponse }]
                });
                continue;
            }

            // 2. Assistant tool call message
            if (message.role === "assistant" && message.functionCall && message.functionName && message.functionName.length > 0) {
                const fc = (typeof message.functionCall === "object")
                    ? message.functionCall
                    : { "name": message.functionName, "args": {} };
                let callPart = {
                    "functionCall": {
                        "name": fc.name,
                        "args": fc.args ?? {}
                    }
                };
                if (fc.id) callPart.functionCall.id = fc.id;
                const sig = fc.thoughtSignature || fc.thought_signature || message.thoughtSignature;
                if (sig && sig.length > 0) callPart.thoughtSignature = sig;

                contents.push({
                    "role": "model",
                    "parts": [callPart]
                });
                continue;
            }

            // 3. Regular assistant text message
            if (message.role === "assistant") {
                let cleanText = (message.responseContent && message.responseContent.length > 0)
                    ? message.responseContent
                    : (message.rawContent || message.content || "");
                // Strip <think> blocks from conversation history so reasoning doesn't pollute subsequent turns
                cleanText = cleanText.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
                if (cleanText.length > 0) {
                    contents.push({
                        "role": "model",
                        "parts": [{ text: cleanText }]
                    });
                }
                continue;
            }

            // 4. User message
            let userText = message.rawContent || message.content || "";
            let userParts = [];
            if (userText.length > 0) {
                userParts.push({ text: userText });
            }
            if (message.fileUri && message.fileUri.length > 0) {
                userParts.push({
                    "file_data": {
                        "mime_type": message.fileMimeType,
                        "file_uri": message.fileUri
                    }
                });
            }
            if (userParts.length > 0) {
                contents.push({
                    "role": "user",
                    "parts": userParts
                });
            }
        }

        // Attached file for the current pending prompt
        if (filePath && filePath.length > 0) {
            if (contents.length > 0) {
                contents[contents.length - 1].parts.unshift({
                    file_data: {
                        mime_type: fileMimeTypeSubstitutionString,
                        file_uri: fileUriSubstitutionString
                    }
                });
            }
        }

        // Merge consecutive turns with the same role to strictly adhere to Gemini alternating turn requirements
        let mergedContents = [];
        for (let i = 0; i < contents.length; i++) {
            const turn = contents[i];
            if (mergedContents.length > 0 && mergedContents[mergedContents.length - 1].role === turn.role) {
                mergedContents[mergedContents.length - 1].parts = [
                    ...mergedContents[mergedContents.length - 1].parts,
                    ...turn.parts
                ];
            } else {
                mergedContents.push(turn);
            }
        }

        // Clean leading and trailing model turns (Gemini requires first turn to be 'user' and last turn to be 'user')
        while (mergedContents.length > 0 && mergedContents[0].role === "model") {
            mergedContents.shift();
        }
        while (mergedContents.length > 0 && mergedContents[mergedContents.length - 1].role === "model") {
            mergedContents.pop();
        }

        let baseData = {
            "contents": mergedContents,
            "tools": tools,
            "system_instruction": {
                "parts": [{ text: systemPrompt }]
            },
            "generationConfig": {},
        };
        if (!model.omit_temperature) baseData.generationConfig.temperature = temperature;
        if (model.thinkingLevel && model.thinkingLevel.length > 0) {
            baseData.generationConfig.thinkingConfig = {
                "thinkingLevel": model.thinkingLevel.toUpperCase(),
            };
            if (model.includeThoughts) baseData.generationConfig.thinkingConfig.includeThoughts = true;
        } else if (model.includeThoughts) {
            baseData.generationConfig.thinkingConfig = {
                "includeThoughts": true,
            };
        }
        if (Object.keys(baseData.generationConfig).length === 0) delete baseData.generationConfig;

        const result = model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
        if (model.extraParams?.generationConfig && baseData.generationConfig) {
            result.generationConfig = Object.assign({}, baseData.generationConfig, model.extraParams.generationConfig);
            if (baseData.generationConfig.thinkingConfig || model.extraParams.generationConfig.thinkingConfig) {
                result.generationConfig.thinkingConfig = Object.assign(
                    {},
                    baseData.generationConfig.thinkingConfig ?? {},
                    model.extraParams.generationConfig.thinkingConfig ?? {}
                );
            }
        }
        return result;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        // Gemini doesn't use Authorization header, key is in URL
        return "";
    }

    function parseResponseLine(line, message) {
        const cleanLine = line.trim();
        if (!cleanLine || cleanLine.startsWith(":")) return {};

        if (cleanLine.startsWith("data:")) {
            const eventData = cleanLine.slice(5).trim();
            if (eventData.length === 0 || eventData === "[DONE]") return {};
            buffer = eventData;
            return parseBuffer(message);
        }

        if (cleanLine.startsWith("[")) {
            buffer += cleanLine.slice(1).trim();
        } else if (cleanLine === "]") {
            buffer += cleanLine.slice(0, -1).trim();
            return parseBuffer(message);
        } else if (cleanLine.startsWith(",")) {
            return parseBuffer(message);
        } else {
            buffer += cleanLine;
            // Handle standalone JSON error object starting with { and ending with }
            if (buffer.startsWith("{") && buffer.endsWith("}")) {
                try {
                    JSON.parse(buffer);
                    return parseBuffer(message);
                } catch (e) {
                    // Not a complete JSON yet, continue buffering
                }
            }
        }
        return {};
    }

    function parseBuffer(message) {
        let finished = false;
        try {
            if (!buffer || buffer.length === 0) return {};
            const dataJson = JSON.parse(buffer);

            // Uploaded file
            if (dataJson.uploadedFile) {
                message.fileUri = dataJson.uploadedFile.uri;
                message.fileMimeType = dataJson.uploadedFile.mimeType;
                return {};
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `\n\n⚠️ **Error ${dataJson.error.code || ''}** (${dataJson.error.status || 'API Error'}): ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                if (isReasoning) {
                    isReasoning = false;
                    message.rawContent += "\n\n</think>\n\n";
                    message.content += "\n\n</think>\n\n";
                }
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            // No candidates?
            if (!dataJson.candidates || dataJson.candidates.length === 0) return {};
            
            const candidate = dataJson.candidates[0];
            if (candidate?.finishReason) {
                finished = true;
            }
            
            const parts = candidate?.content?.parts ?? [];

            // Function call handling
            const functionCallPart = parts.find(part => part.functionCall);
            if (functionCallPart) {
                const fc = functionCallPart.functionCall;
                const sig = functionCallPart.thoughtSignature || functionCallPart.thought_signature || candidate?.thoughtSignature || candidate?.thought_signature || "";
                const call = {
                    name: fc.name,
                    args: fc.args ?? {},
                };
                if (fc.id) call.id = fc.id;
                if (sig.length > 0) call.thoughtSignature = sig;
                message.functionName = call.name;
                message.functionCall = call;
                message.thoughtSignature = sig;
                if (isReasoning) {
                    isReasoning = false;
                    message.rawContent += "\n\n</think>\n\n";
                    message.content += "\n\n</think>\n\n";
                }
                return { functionCall: call, finished: finished };
            }

            // Normal text & reasoning response
            let newResponseText = "";
            let newThoughtText = "";
            parts.forEach(part => {
                if (part.text === undefined || part.text === null) return;
                if (part.thought) {
                    newThoughtText += part.text;
                } else {
                    newResponseText += part.text;
                }
            });

            if (newThoughtText.length > 0) {
                message.reasoningContent = (message.reasoningContent || "") + newThoughtText;
                if (!isReasoning) {
                    isReasoning = true;
                    const startTag = "\n\n<think>\n\n";
                    message.rawContent += startTag;
                    message.content += startTag;
                }
                message.rawContent += newThoughtText;
                message.content += newThoughtText;
            }

            if (newResponseText.length > 0) {
                message.responseContent = (message.responseContent || "") + newResponseText;
                if (isReasoning) {
                    isReasoning = false;
                    const endTag = "\n\n</think>\n\n";
                    message.rawContent += endTag;
                    message.content += endTag;
                }
                message.rawContent += newResponseText;
                message.content += newResponseText;
            }
            
            // Grounding annotations and metadata
            const annotationSources = candidate?.groundingMetadata?.groundingChunks?.map(chunk => ({
                "type": "url_citation",
                "text": chunk?.web?.title,
                "url": chunk?.web?.uri,
            })) ?? [];

            const annotations = candidate?.groundingMetadata?.groundingSupports?.map(citation => ({
                "type": "url_citation",
                "start_index": citation.segment?.startIndex,
                "end_index": citation.segment?.endIndex,
                "text": citation?.segment?.text,
                "url": annotationSources[citation.groundingChunkIndices?.[0]]?.url,
                "sources": citation.groundingChunkIndices
            })) ?? [];

            if (annotationSources.length > 0) message.annotationSources = annotationSources;
            if (annotations.length > 0) message.annotations = annotations;
            if (candidate?.groundingMetadata?.webSearchQueries) {
                message.searchQueries = candidate.groundingMetadata.webSearchQueries;
            }

            // Usage metadata
            if (dataJson.usageMetadata) {
                return {
                    tokenUsage: {
                        input: dataJson.usageMetadata.promptTokenCount ?? -1,
                        output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                        total: dataJson.usageMetadata.totalTokenCount ?? -1
                    },
                    finished: finished
                };
            }
            
        } catch (e) {
            console.log("[AI] Gemini: Could not parse buffer: ", e);
            message.rawContent += buffer;
            message.content += buffer;
        } finally {
            buffer = "";
        }
        return { finished: finished };
    }

    function onRequestFinished(message) {
        if (isReasoning) {
            isReasoning = false;
            const endTag = "\n\n</think>\n\n";
            message.rawContent += endTag;
            message.content += endTag;
        }
        if (buffer && buffer.trim().length > 0) {
            return parseBuffer(message);
        }
        return {};
    }
    
    function reset() {
        buffer = "";
        isReasoning = false;
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = CF.FileUtils.trimFileProtocol(filePath);
        let content = "";

        content += `IMAGE_PATH='${CF.StringUtils.shellSingleQuoteEscape(trimmedFilePath)}'\n`;
        content += `${fileMimeTypeVarName}=$(file -b --mime-type "$IMAGE_PATH")\n`;
        content += 'NUM_BYTES=$(wc -c < "${IMAGE_PATH}")\n';
        content += 'tmp_header_file="/tmp/quickshell/ai/upload-header.tmp"\n';
        content += 'tmp_file_info_file="/tmp/quickshell/ai/file-info.json.tmp"\n';

        // Initial resumable request defining metadata.
        content += 'curl -s "https://generativelanguage.googleapis.com/upload/v1beta/files"'
            + ` -H "x-goog-api-key: \$${apiKeyEnvVarName}"`
            + ' -D "$tmp_header_file"'
            + ' -H "X-Goog-Upload-Protocol: resumable"'
            + ' -H "X-Goog-Upload-Command: start"'
            + ' -H "X-Goog-Upload-Header-Content-Length: ${NUM_BYTES}"'
            + ` -H "X-Goog-Upload-Header-Content-Type: \${${fileMimeTypeVarName}}"`
            + ' -H "Content-Type: application/json"'
            + ` -d "{\\"file\\": {\\"display_name\\": \\"Image\\"}}" 2> /dev/null`
            + '\n';

        // Get file upload header
        content += 'upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\\r")\n';
        content += 'rm -f "${tmp_header_file}"\n';

        // Upload the actual file
        content += 'curl -s "${upload_url}"'
            + ` -H "x-goog-api-key: \$${apiKeyEnvVarName}"`
            + ' -H "Content-Length: ${NUM_BYTES}"'
            + ' -H "X-Goog-Upload-Offset: 0"'
            + ' -H "X-Goog-Upload-Command: upload, finalize"'
            + ' --data-binary "@${IMAGE_PATH}" 2> /dev/null > "${tmp_file_info_file}"'
            + '\n';

        content += `${fileUriVarName}=$(jq -r ".file.uri" "$tmp_file_info_file")\n`;
        content += 'rm -f "$tmp_file_info_file"\n';
        content += `sed -i "s|${fileUriSubstitutionString}|\$${fileUriVarName}|g" /tmp/quickshell/ai/request.json\n`;
        content += `sed -i "s|${fileMimeTypeSubstitutionString}|\$${fileMimeTypeVarName}|g" /tmp/quickshell/ai/request.json\n`;
        content += `printf "{\\"uploadedFile\\": {\\"uri\\": \\"$${fileUriVarName}\\", \\"mimeType\\": \\"$${fileMimeTypeVarName}\\"}}\\n,\\n"\n`;

        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        return scriptContent;
    }
}

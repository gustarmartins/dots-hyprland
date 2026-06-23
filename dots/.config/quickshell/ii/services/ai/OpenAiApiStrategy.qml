import QtQuick

ApiStrategy {
    property bool isReasoning: false
    property var toolCallFragments: ({})
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let requestMessages = [
            {role: "system", content: systemPrompt},
            ...messages.map(message => {
                const hasFunctionResponse = message.functionResponse != undefined && message.functionName.length > 0;
                if (hasFunctionResponse) {
                    return {
                        "role": "tool",
                        "content": message.functionResponse,
                        "tool_call_id": message.functionCall?.id ?? message.functionName,
                    };
                }

                let messageData = {
                    "role": message.role,
                    "content": message.rawContent,
                };
                if (model.includeReasoningInHistory && message.reasoningContent?.length > 0) {
                    messageData.reasoning_content = message.reasoningContent;
                    messageData.content = message.responseContent || "";
                }
                if (message.role === "assistant" && message.functionCall?.id) {
                    messageData.content = message.responseContent || "";
                    messageData.tool_calls = [{
                        "id": message.functionCall.id,
                        "type": "function",
                        "function": {
                            "name": message.functionCall.name,
                            "arguments": JSON.stringify(message.functionCall.args ?? {}),
                        },
                    }];
                }
                return messageData;
            }),
        ];
        let baseData = {
            "model": model.model,
            "messages": requestMessages,
            "stream": true,
            "tools": tools,
        };
        if (!model.omit_temperature) baseData.temperature = temperature;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        // console.log("[AI] OpenAI: Data:", cleanData);
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            return { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            let newContent = "";

            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;
            const toolCalls = dataJson.choices[0]?.delta?.tool_calls ?? dataJson.choices[0]?.message?.tool_calls;

            if (toolCalls) {
                toolCalls.forEach(toolCall => {
                    const index = toolCall.index ?? 0;
                    const current = toolCallFragments[index] ?? {
                        id: "",
                        type: "function",
                        function: {
                            name: "",
                            arguments: "",
                        },
                    };
                    if (toolCall.id) current.id = toolCall.id;
                    if (toolCall.type) current.type = toolCall.type;
                    if (toolCall.function?.name) current.function.name += toolCall.function.name;
                    if (toolCall.function?.arguments) current.function.arguments += toolCall.function.arguments;
                    toolCallFragments[index] = current;
                });
            }

            if (dataJson.choices[0]?.finish_reason === "tool_calls" || dataJson.choices[0]?.finish_reason === "tool_call") {
                const firstCall = toolCallFragments[Object.keys(toolCallFragments)[0]];
                if (firstCall) {
                    let functionArgs = {};
                    try {
                        functionArgs = JSON.parse(firstCall.function.arguments || "{}");
                    } catch (e) {
                        console.log("[AI] OpenAI: Could not parse tool call arguments: ", e);
                    }
                    const call = {
                        id: firstCall.id,
                        name: firstCall.function.name,
                        args: functionArgs,
                    };
                    message.functionName = call.name;
                    message.functionCall = call;
                    const callContent = `\n\n[[ Function: ${call.name}(${JSON.stringify(call.args, null, 2)}) ]]\n`;
                    message.rawContent += callContent;
                    message.content += callContent;
                    toolCallFragments = ({});
                    return { functionCall: call };
                }
            }

            if (responseContent && responseContent.length > 0) {
                message.responseContent += responseContent;
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                message.reasoningContent += responseReasoning;
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }
            
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        // OpenAI format doesn't need special finish handling
        return {};
    }
    
    function reset() {
        isReasoning = false;
        toolCallFragments = ({});
    }

}

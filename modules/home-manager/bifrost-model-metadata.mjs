const DEFAULT_CONTEXT_WINDOW = 128000;
const MAX_OUTPUT_TOKENS = 32000;

function positiveInteger(value) {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : undefined;
}

export function mapBifrostModel(model) {
  const id = typeof model?.id === "string" ? model.id : "";
  const contextWindow =
    positiveInteger(model?.context_window) ??
    positiveInteger(model?.context_length) ??
    positiveInteger(model?.max_input_tokens) ??
    DEFAULT_CONTEXT_WINDOW;
  const advertisedMaxOutput = positiveInteger(model?.max_output_tokens) ?? MAX_OUTPUT_TOKENS;

  return {
    id,
    name: model?.name || id,
    reasoning: /thinking|reasoning/i.test(id),
    input: ["text"],
    cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0},
    contextWindow,
    maxTokens: Math.min(advertisedMaxOutput, MAX_OUTPUT_TOKENS),
  };
}

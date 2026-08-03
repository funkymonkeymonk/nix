# vllm-mlx streaming regression tests (functional, package-level)
#
# Drives the real stream_chat_completion() from the packaged vllm-mlx with a
# fake engine reproducing the production failure: gemma4-31b emits a complete
# canonical tool call (including <tool_call|>) in one delta, then a terminal
# engine output carrying only the <turn|> end-of-turn token. The gemma4 tool
# parser finds nothing new in that delta and swallows it with `continue`, so
# without a terminal-chunk guard no SSE chunk ever carries finish_reason and
# OpenAI clients (pi) abort with "Stream ended without finish_reason".
#
# Scenario 1 (reasoning parser enabled) is the exact live failure; it is
# covered by the repo's <turn|> stripping postPatch. Scenario 2 (no reasoning
# parser) exercises the same swallow class on the plain tool-parser branch,
# which only the terminal-chunk guard fixes.
{pkgs, ...}: let
  reproScript = pkgs.writeText "vllm-mlx-finish-reason-repro.py" ''
    """Regression repro: terminal engine output swallowed by the tool parser."""
    import asyncio
    import json

    import vllm_mlx.server as S
    from vllm_mlx.api.models import ChatCompletionRequest
    from vllm_mlx.engine.base import GenerationOutput
    from vllm_mlx.reasoning import get_parser as get_reasoning_parser


    class FakeEngine:
        """Minimal engine stand-in matching the gemma4-31b production stream."""

        model_name = "gemma4-31b"
        tokenizer = None

        async def stream_chat(self, messages=None, **kwargs):
            # 1. Thinking block (Gemma 4 channel protocol)
            for piece in ["<|channel>thought\n", "Let", " me", " check", ".", "\n<channel|>\n"]:
                yield GenerationOutput(
                    text=piece,
                    new_text=piece,
                    prompt_tokens=10,
                    completion_tokens=1,
                    finish_reason=None,
                    finished=False,
                )
            # 2. Complete canonical tool call markup INCLUDING the end marker,
            #    all in one delta (what gemma4-31b produced in production).
            #    The parser emits the tool_calls chunk here with
            #    finish_reason=null (finished=False).
            markup = '<|tool_call>call:get_weather{<|"|>city<|"|>: <|"|>Paris<|"|>}<tool_call|>'
            yield GenerationOutput(
                text=markup,
                new_text=markup,
                prompt_tokens=10,
                completion_tokens=20,
                finish_reason=None,
                finished=False,
            )
            # 3. Terminal output: bare end-of-turn token, engine reports
            #    finished (stop-string hit on <turn|>). The tool parser
            #    re-enters, finds nothing new to emit and swallows this delta
            #    with `continue` — the bug path: no finish_reason chunk.
            yield GenerationOutput(
                text="<turn|>",
                new_text="<turn|>",
                prompt_tokens=10,
                completion_tokens=21,
                finish_reason="stop",
                finished=True,
            )


    def make_request():
        return ChatCompletionRequest(
            model="gemma4-31b",
            messages=[{"role": "user", "content": "weather in Paris?"}],
            tools=[
                {
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "description": "Get weather",
                        "parameters": {
                            "type": "object",
                            "properties": {"city": {"type": "string"}},
                            "required": ["city"],
                        },
                    },
                }
            ],
        )


    async def run_scenario(name, reasoning_parser):
        S._enable_auto_tool_choice = True
        S._tool_call_parser = "gemma4"
        S._tool_parser_instance = None
        S._reasoning_parser = reasoning_parser

        request = make_request()
        finish_reasons = []
        tool_chunks = 0
        async for frame in S.stream_chat_completion(
            FakeEngine(), request.messages, request, stop=["<turn|>"]
        ):
            assert frame.startswith("data: "), f"unexpected frame: {frame!r}"
            payload = frame[len("data: ") :].strip()
            if payload == "[DONE]":
                continue
            chunk = json.loads(payload)
            choice = chunk["choices"][0]
            if choice["delta"].get("tool_calls"):
                tool_chunks += 1
            if choice.get("finish_reason"):
                finish_reasons.append(choice["finish_reason"])

        print(f"[{name}] tool_chunks={tool_chunks} finish_reasons={finish_reasons}")
        assert tool_chunks == 1, (
            f"[{name}] expected exactly one tool_calls chunk, got {tool_chunks}"
        )
        assert finish_reasons == ["tool_calls"], (
            f"[{name}] stream must terminate with a finish_reason='tool_calls' "
            f"chunk; got finish_reasons={finish_reasons}"
        )


    async def main():
        await run_scenario(
            "reasoning-parser", get_reasoning_parser("gemma4")()
        )
        await run_scenario("no-reasoning-parser", None)
        print("OK: terminal finish_reason chunk emitted in both scenarios")


    asyncio.run(main())
  '';
in {
  vllmMlxFinishReasonTest =
    pkgs.runCommand "test-vllm-mlx-finish-reason"
    {
      env.HF_HUB_OFFLINE = "1";
      env.TRANSFORMERS_OFFLINE = "1";
      env.HOME = "/tmp/vllm-mlx-test-home";
    }
    ''
      mkdir -p "$HOME"
      # Reuse the exact site-packages closure that wraps the vllm-mlx binary
      # (withPackages skips buildPythonApplication outputs).
      PYTHONPATH=$(grep -oP "(?<=')/nix/store/[^']+site-packages(?=')" \
        ${pkgs.vllm-mlx}/bin/.vllm-mlx-wrapped | tr '\n' ':')
      export PYTHONPATH
      ${pkgs.python3}/bin/python ${reproScript}
      touch $out
    '';
}

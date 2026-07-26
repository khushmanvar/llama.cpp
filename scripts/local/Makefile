start-local:
	bash llama-hf ggml-org/gemma-3-270m-it-qat-GGUF:Q4_0

test:
	curl -sS http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"What is the capital of France?"}]}' | python -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'].strip())"
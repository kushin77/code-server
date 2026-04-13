#!/usr/bin/env python3
"""
Fine-tune an Ollama model on the prepared dataset.
Wraps Unsloth / HuggingFace Trainer for LoRA fine-tuning.
Usage: python3 scripts/finetune.py [--data finetune_data.jsonl] [--model qwen2.5-coder:7b-instruct-q8_0]
"""
import argparse, json, sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="finetune_data.jsonl")
    parser.add_argument("--model", default="unsloth/Qwen2.5-Coder-7B-Instruct-bnb-4bit")
    parser.add_argument("--output-dir", default="./finetune-output")
    parser.add_argument("--max-steps", type=int, default=100)
    args = parser.parse_args()

    try:
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
        from datasets import Dataset
    except ImportError:
        print("ERROR: Install training deps: pip install unsloth trl datasets transformers", file=sys.stderr)
        sys.exit(1)

    data = Path(args.data)
    if not data.exists():
        print(f"ERROR: dataset not found: {data}. Run prepare_finetune_dataset.py first.", file=sys.stderr)
        sys.exit(1)

    records = [json.loads(l) for l in data.read_text().splitlines() if l.strip()]
    texts = [f"### Instruction:\n{r['instruction']}\n\n### Input:\n{r['input']}\n\n### Response:\n{r['output']}" for r in records]
    dataset = Dataset.from_dict({"text": texts})

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model, max_seq_length=4096, load_in_4bit=True
    )
    model = FastLanguageModel.get_peft_model(
        model, r=16, lora_alpha=16, lora_dropout=0,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=4096,
        args=TrainingArguments(
            output_dir=args.output_dir,
            max_steps=args.max_steps,
            per_device_train_batch_size=2,
            gradient_accumulation_steps=4,
            learning_rate=2e-4,
            fp16=True,
            logging_steps=10,
            save_steps=50,
        ),
    )
    trainer.train()
    model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)
    print(f"Fine-tuning complete. Model saved to {args.output_dir}", file=sys.stderr)

if __name__ == "__main__":
    main()

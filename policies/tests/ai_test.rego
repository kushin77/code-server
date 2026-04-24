package ai.test

import data.ai.prompt_safety
import data.ai.model_allowlist

test_prompt_safety_allow {
    prompt_safety.allow with input as {"findings": []}
}

test_prompt_safety_deny {
    not prompt_safety.allow with input as {"findings": ["SECRET_DETECTED"]}
}

test_model_allowlist_allow {
    model_allowlist.allow with input as {"model": "llama3:8b"}
}

test_model_allowlist_deny {
    not model_allowlist.allow with input as {"model": "gpt-4"}
}

#!/usr/bin/env rego
# @file        policies/tests/ai_test.rego
# @module      tests
# @description Unit tests for AI policies
# @owner       ai
# @status      production-ready

package policy.ai.prompt_safety_test

import data.policy.ai.prompt_safety

# Test: Allow safe prompt
test_allow_safe_prompt {
    result := prompt_safety.allow with input as {
        "prompt": "What is the capital of France?"
    }
    result == true
}

# Test: Deny prompt with secret
test_deny_prompt_with_secret {
    result := prompt_safety.allow with input as {
        "prompt": "Here is my AWS secret key: aws_secret_key=wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    }
    result == false
}

# Test: Deny prompt with PII
test_deny_prompt_with_pii {
    result := prompt_safety.allow with input as {
        "prompt": "My SSN is 123-45-6789"
    }
    result == false
}

# Test: Allow prompt with generic numbers (not SSN format)
test_allow_generic_numbers {
    result := prompt_safety.allow with input as {
        "prompt": "The number 42 is interesting"
    }
    result == true
}

---

package policy.ai.model_allowlist_test

import data.policy.ai.model_allowlist

# Test: Allow ELITE user to use GPT-4
test_allow_elite_gpt4 {
    result := model_allowlist.allow with input as {
        "model": "gpt-4",
        "user_reputation_tier": "ELITE"
    }
    result == true
}

# Test: Allow STANDARD user to use Llama3:8B
test_allow_standard_llama3_8b {
    result := model_allowlist.allow with input as {
        "model": "llama3:8b",
        "user_reputation_tier": "STANDARD"
    }
    result == true
}

# Test: Deny STANDARD user from using GPT-4
test_deny_standard_gpt4 {
    result := model_allowlist.deny with input as {
        "model": "gpt-4-turbo",
        "user_reputation_tier": "STANDARD"
    }
    result == true
}

# Test: Deny RESTRICTED user from using CodeLlama
test_deny_restricted_codellama {
    result := model_allowlist.deny with input as {
        "model": "codellama:13b",
        "user_reputation_tier": "RESTRICTED"
    }
    result == true
}

# Test: Allow RESTRICTED user to use Mistral
test_allow_restricted_mistral {
    result := model_allowlist.allow with input as {
        "model": "mistral:7b",
        "user_reputation_tier": "RESTRICTED"
    }
    result == true
}

#!/usr/bin/env python3
# @file        apps/prompt-gateway/routes_batch.py
# @module      prompt-gateway/routes
# @description Batch processing API endpoints for Prompt Gateway
#
# Provides REST API for submitting, monitoring, and retrieving results of batch prompt processing

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
import json

from batch import BatchProcessor, BatchStatus

router = APIRouter(prefix="/api/batch", tags=["batch"])
batch_processor = BatchProcessor(max_concurrent=10, timeout_per_prompt_sec=60)


class BatchPromptRequest(BaseModel):
    """Individual prompt in batch"""
    prompt: str
    model: str = "llama3:8b"


class BatchSubmitRequest(BaseModel):
    """Submit batch of prompts"""
    prompts: List[BatchPromptRequest]


class BatchStatusResponse(BaseModel):
    """Batch status response"""
    batch_id: str
    status: str
    total_items: int
    completed_items: int
    failed_items: int
    progress_percent: int
    created_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None


class BatchItemResult(BaseModel):
    """Single batch item result"""
    id: str
    prompt: str
    model: str
    status: str
    result: Optional[str] = None
    error: Optional[str] = None
    tokens_used: int
    latency_ms: float
    completed_at: Optional[str] = None


class BatchResultsResponse(BaseModel):
    """Complete batch results"""
    batch_id: str
    status: str
    items: List[BatchItemResult]
    summary: dict


@router.post("/submit", response_model=dict)
async def submit_batch(user_id: str, request: BatchSubmitRequest) -> dict:
    """
    Submit batch of prompts for processing
    
    Returns batch_id for tracking
    """
    if not request.prompts:
        raise HTTPException(status_code=400, detail="At least one prompt required")
    
    if len(request.prompts) > 10000:
        raise HTTPException(status_code=400, detail="Maximum 10,000 prompts per batch")
    
    batch_id = await batch_processor.submit_batch(
        user_id,
        [{"prompt": p.prompt, "model": p.model} for p in request.prompts]
    )
    
    return {
        "batch_id": batch_id,
        "message": f"Batch submitted with {len(request.prompts)} prompts",
        "status_url": f"/api/batch/{batch_id}/status",
        "results_url": f"/api/batch/{batch_id}/results"
    }


@router.get("/{batch_id}/status", response_model=BatchStatusResponse)
async def get_batch_status(batch_id: str) -> dict:
    """Get current status and progress of batch"""
    status = batch_processor.get_batch_status(batch_id)
    
    if not status:
        raise HTTPException(status_code=404, detail="Batch not found")
    
    return status


@router.get("/{batch_id}/results", response_model=BatchResultsResponse)
async def get_batch_results(batch_id: str) -> dict:
    """Get all results from completed batch"""
    results = batch_processor.get_batch_results(batch_id)
    
    if not results:
        raise HTTPException(status_code=404, detail="Batch not found")
    
    return results


@router.get("/list")
async def list_user_batches(user_id: str) -> dict:
    """List all batches for user"""
    batches = batch_processor.list_user_batches(user_id)
    
    return {
        "user_id": user_id,
        "batches": batches,
        "total_count": len(batches)
    }


@router.delete("/{batch_id}/cancel", response_model=dict)
async def cancel_batch(batch_id: str) -> dict:
    """Cancel pending batch"""
    success = await batch_processor.cancel_batch(batch_id)
    
    if not success:
        raise HTTPException(status_code=400, detail="Batch cannot be cancelled (already completed or failed)")
    
    return {"batch_id": batch_id, "message": "Batch cancelled"}

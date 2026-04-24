#!/usr/bin/env python3
# @file        apps/prompt-gateway/batch.py
# @module      prompt-gateway/batch
# @description Batch processing handler for bulk prompt evaluations
#
# Implements batch endpoint for processing multiple prompts in parallel
# with optimized resource utilization and progress tracking.

import asyncio
import uuid
from typing import List, Dict, Optional
from dataclasses import dataclass, field
from enum import Enum
from datetime import datetime
import json

class BatchStatus(Enum):
    """Batch processing states"""
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    PARTIAL = "partial"  # Some succeeded, some failed


@dataclass
class BatchItem:
    """Individual prompt in a batch"""
    id: str
    prompt: str
    model: str
    user_id: str
    status: str = "pending"
    result: Optional[str] = None
    error: Optional[str] = None
    tokens_used: int = 0
    latency_ms: float = 0.0
    created_at: float = field(default_factory=lambda: datetime.utcnow().timestamp())
    completed_at: Optional[float] = None


@dataclass
class BatchRequest:
    """Batch processing request"""
    batch_id: str
    user_id: str
    items: List[BatchItem]
    status: BatchStatus = BatchStatus.PENDING
    total_items: int = 0
    completed_items: int = 0
    failed_items: int = 0
    created_at: float = field(default_factory=lambda: datetime.utcnow().timestamp())
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    results_url: Optional[str] = None
    
    def __post_init__(self):
        self.total_items = len(self.items)


class BatchProcessor:
    """
    Process multiple prompts in parallel batches.
    
    Features:
    - Parallel processing (configurable concurrency)
    - Progress tracking
    - Error recovery per item
    - Results aggregation
    - Webhook notifications (Phase 2)
    """
    
    def __init__(self, max_concurrent: int = 10, timeout_per_prompt_sec: int = 60):
        self.max_concurrent = max_concurrent
        self.timeout = timeout_per_prompt_sec
        self.active_batches: Dict[str, BatchRequest] = {}
    
    async def submit_batch(self, user_id: str, prompts: List[Dict]) -> str:
        """
        Submit batch of prompts for processing.
        
        Args:
            user_id: User submitting batch
            prompts: List of dicts with "prompt", "model" keys
        
        Returns:
            batch_id for tracking
        """
        batch_id = str(uuid.uuid4())
        items = [
            BatchItem(
                id=str(uuid.uuid4()),
                prompt=p["prompt"],
                model=p.get("model", "llama3:8b"),
                user_id=user_id
            )
            for p in prompts
        ]
        
        batch = BatchRequest(
            batch_id=batch_id,
            user_id=user_id,
            items=items
        )
        
        self.active_batches[batch_id] = batch
        
        # Start processing in background
        asyncio.create_task(self._process_batch(batch_id))
        
        return batch_id
    
    async def _process_batch(self, batch_id: str) -> None:
        """Process batch items in parallel"""
        batch = self.active_batches[batch_id]
        batch.status = BatchStatus.PROCESSING
        batch.started_at = datetime.utcnow().timestamp()
        
        # Process in chunks of max_concurrent
        for i in range(0, len(batch.items), self.max_concurrent):
            chunk = batch.items[i:i+self.max_concurrent]
            
            # Process chunk concurrently
            tasks = [
                self._process_item(batch, item)
                for item in chunk
            ]
            
            await asyncio.gather(*tasks, return_exceptions=True)
        
        # Mark batch complete
        batch.completed_at = datetime.utcnow().timestamp()
        
        # Determine final status
        if batch.failed_items == 0:
            batch.status = BatchStatus.COMPLETED
        elif batch.failed_items < batch.total_items:
            batch.status = BatchStatus.PARTIAL
        else:
            batch.status = BatchStatus.FAILED
    
    async def _process_item(self, batch: BatchRequest, item: BatchItem) -> None:
        """Process single batch item"""
        try:
            start_time = datetime.utcnow().timestamp()
            
            # TODO: Call actual Prompt Gateway process_prompt here
            # For now, simulate processing
            await asyncio.sleep(0.1)  # Placeholder
            
            item.status = "completed"
            item.result = f"Response to: {item.prompt[:50]}..."
            item.tokens_used = 150
            item.latency_ms = (datetime.utcnow().timestamp() - start_time) * 1000
            item.completed_at = datetime.utcnow().timestamp()
            
            batch.completed_items += 1
        
        except Exception as e:
            item.status = "failed"
            item.error = str(e)
            item.completed_at = datetime.utcnow().timestamp()
            batch.failed_items += 1
    
    def get_batch_status(self, batch_id: str) -> Optional[Dict]:
        """Get batch status and progress"""
        batch = self.active_batches.get(batch_id)
        
        if not batch:
            return None
        
        return {
            "batch_id": batch_id,
            "status": batch.status.value,
            "total_items": batch.total_items,
            "completed_items": batch.completed_items,
            "failed_items": batch.failed_items,
            "progress_percent": round(
                (batch.completed_items + batch.failed_items) / batch.total_items * 100
                if batch.total_items > 0 else 0
            ),
            "created_at": datetime.fromtimestamp(batch.created_at).isoformat(),
            "started_at": datetime.fromtimestamp(batch.started_at).isoformat() if batch.started_at else None,
            "completed_at": datetime.fromtimestamp(batch.completed_at).isoformat() if batch.completed_at else None,
        }
    
    def get_batch_results(self, batch_id: str) -> Optional[Dict]:
        """Get all results from completed batch"""
        batch = self.active_batches.get(batch_id)
        
        if not batch:
            return None
        
        return {
            "batch_id": batch_id,
            "status": batch.status.value,
            "items": [
                {
                    "id": item.id,
                    "prompt": item.prompt,
                    "model": item.model,
                    "status": item.status,
                    "result": item.result,
                    "error": item.error,
                    "tokens_used": item.tokens_used,
                    "latency_ms": item.latency_ms,
                    "completed_at": datetime.fromtimestamp(item.completed_at).isoformat() if item.completed_at else None,
                }
                for item in batch.items
            ],
            "summary": {
                "total_items": batch.total_items,
                "successful_items": batch.completed_items,
                "failed_items": batch.failed_items,
                "total_tokens": sum(item.tokens_used for item in batch.items),
                "avg_latency_ms": sum(item.latency_ms for item in batch.items) / len(batch.items) if batch.items else 0,
                "duration_seconds": batch.completed_at - batch.started_at if batch.completed_at and batch.started_at else None,
            }
        }
    
    def list_user_batches(self, user_id: str) -> List[Dict]:
        """List all batches for a user"""
        user_batches = [
            batch for batch in self.active_batches.values()
            if batch.user_id == user_id
        ]
        
        return [
            {
                "batch_id": batch.batch_id,
                "status": batch.status.value,
                "total_items": batch.total_items,
                "progress_percent": round(
                    (batch.completed_items + batch.failed_items) / batch.total_items * 100
                    if batch.total_items > 0 else 0
                ),
                "created_at": datetime.fromtimestamp(batch.created_at).isoformat(),
            }
            for batch in user_batches
        ]
    
    async def cancel_batch(self, batch_id: str) -> bool:
        """Cancel pending batch. Returns success status."""
        batch = self.active_batches.get(batch_id)
        
        if not batch or batch.status in [BatchStatus.COMPLETED, BatchStatus.FAILED]:
            return False
        
        batch.status = BatchStatus.FAILED
        batch.completed_at = datetime.utcnow().timestamp()
        return True

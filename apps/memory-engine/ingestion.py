"""
@file apps/memory-engine/ingestion.py
@description Document ingestion and chunking for organizational memory
@governance GOV-002
"""

from log import get_logger
from typing import List, Optional
from dataclasses import dataclass

logger = get_logger(__name__)


@dataclass
class ChunkConfig:
    """Configuration for text chunking."""
    chunk_size: int = 512  # tokens, approximate
    chunk_overlap: int = 50  # tokens for context preservation
    separator: str = "\n\n"


class DocumentChunker:
    """Split documents into chunks for embedding."""

    def __init__(self, config: Optional[ChunkConfig] = None):
        self.config = config or ChunkConfig()

    def chunk_document(self, text: str, metadata: Optional[dict] = None) -> List[dict]:
        """
        Split document into chunks.
        
        Args:
            text: Document text
            metadata: Optional metadata to attach to chunks
            
        Returns:
            List of chunks with metadata
        """
        chunks = []
        
        # Split by separator
        paragraphs = text.split(self.config.separator)
        
        current_chunk = ""
        for para in paragraphs:
            if len(current_chunk.split()) + len(para.split()) > self.config.chunk_size:
                if current_chunk:
                    chunks.append({
                        "text": current_chunk.strip(),
                        "metadata": metadata or {},
                    })
                current_chunk = para
            else:
                if current_chunk:
                    current_chunk += self.config.separator + para
                else:
                    current_chunk = para

        # Add final chunk
        if current_chunk:
            chunks.append({
                "text": current_chunk.strip(),
                "metadata": metadata or {},
            })

        logger.info(f"Chunked document into {len(chunks)} chunks")
        return chunks

    def chunk_github_issue(self, issue_data: dict) -> List[dict]:
        """
        Extract and chunk GitHub issue content.
        
        Args:
            issue_data: GitHub issue dict with title, body, etc.
            
        Returns:
            List of chunks
        """
        text = f"# {issue_data.get('title', 'Untitled')}\n\n"
        text += issue_data.get('body', '')
        
        if issue_data.get('labels'):
            text += "\n\n## Labels\n" + ", ".join(
                [l.get('name', '') for l in issue_data['labels']]
            )

        chunks = self.chunk_document(text, metadata={
            "source_type": "github_issue",
            "issue_number": issue_data.get('number'),
            "url": issue_data.get('html_url'),
            "created_at": issue_data.get('created_at'),
        })

        return chunks

    def chunk_runbook(self, content: str, title: str) -> List[dict]:
        """
        Extract and chunk runbook content.
        
        Args:
            content: Markdown runbook content
            title: Runbook title
            
        Returns:
            List of chunks
        """
        text = f"# {title}\n\n{content}"
        
        chunks = self.chunk_document(text, metadata={
            "source_type": "runbook",
            "title": title,
        })

        return chunks

    def chunk_session_report(self, content: str, session_date: str) -> List[dict]:
        """
        Extract and chunk session completion report.
        
        Args:
            content: Report content
            session_date: Date string
            
        Returns:
            List of chunks
        """
        text = content
        
        chunks = self.chunk_document(text, metadata={
            "source_type": "session_report",
            "session_date": session_date,
        })

        return chunks


class DocumentNormalizer:
    """Normalize documents for consistent ingestion."""

    @staticmethod
    def normalize_markdown(text: str) -> str:
        """Normalize markdown text."""
        # Remove excessive whitespace
        text = '\n'.join(line.rstrip() for line in text.split('\n'))
        # Remove multiple blank lines
        while '\n\n\n' in text:
            text = text.replace('\n\n\n', '\n\n')
        return text.strip()

    @staticmethod
    def extract_summary(text: str, max_chars: int = 200) -> str:
        """Extract summary from text."""
        # Take first paragraph or first max_chars
        paragraphs = text.split('\n\n')
        if paragraphs:
            first_para = paragraphs[0].strip()
            if len(first_para) > max_chars:
                return first_para[:max_chars] + "..."
            return first_para
        return ""

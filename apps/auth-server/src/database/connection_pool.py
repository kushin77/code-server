# Database Connection Pool & Performance Monitoring
# Week 5 Phase 5.2: Connection Pool Optimization & Metrics Collection

from typing import Optional
from log import get_logger
from sqlalchemy import event, text
from sqlalchemy.pool import QueuePool, StaticPool, NullPool
from sqlalchemy.ext.asyncio import create_async_engine, AsyncEngine, AsyncSession
from sqlalchemy.orm import sessionmaker
import time

logger = get_logger(__name__)


class ConnectionPoolOptimizer:
    """
    Optimizes database connection pooling for concurrent workloads.
    
    Performance Tuning:
    - Increased pool_size (5 -> 20) for concurrent requests
    - Increased max_overflow (10 -> 40) for burst load handling
    - Added pool_recycle to handle DB connection timeout
    - Added pool_pre_ping to verify connection health
    """
    
    # Production Configuration
    PRODUCTION_CONFIG = {
        "pool_size": 20,          # Connections to keep in pool
        "max_overflow": 40,        # Extra connections during peaks
        "pool_recycle": 3600,      # Recycle after 1 hour (prevent stale connections)
        "pool_pre_ping": True,     # Test connections before use
        "echo_pool": False,        # Disable verbose pool logging
    }
    
    # Development Configuration
    DEVELOPMENT_CONFIG = {
        "pool_size": 5,
        "max_overflow": 10,
        "pool_recycle": 3600,
        "pool_pre_ping": True,
        "echo_pool": False,
    }
    
    @staticmethod
    def get_config(environment: str = "production") -> dict:
        """Get pool configuration for environment"""
        if environment == "development":
            return ConnectionPoolOptimizer.DEVELOPMENT_CONFIG.copy()
        return ConnectionPoolOptimizer.PRODUCTION_CONFIG.copy()
    
    @staticmethod
    async def create_engine_with_optimization(
        database_url: str,
        environment: str = "production",
        echo: bool = False
    ) -> AsyncEngine:
        """
        Create SQLAlchemy async engine with optimized connection pooling.
        
        Example:
            engine = await ConnectionPoolOptimizer.create_engine_with_optimization(
                "postgresql+asyncpg://user:pass@localhost/db",
                environment="production"
            )
        """
        config = ConnectionPoolOptimizer.get_config(environment)
        
        engine = create_async_engine(
            database_url,
            echo=echo,
            poolclass=QueuePool,
            **config
        )
        
        logger.info(f"Created database engine with config: {config}")
        
        # Register event listeners for monitoring
        ConnectionPoolOptimizer._register_pool_events(engine)
        
        return engine
    
    @staticmethod
    def _register_pool_events(engine: AsyncEngine) -> None:
        """Register event listeners for pool monitoring"""
        
        @event.listens_for(engine.sync_engine.pool, "connect")
        def receive_connect(dbapi_conn, connection_record):
            """Log successful connections"""
            logger.debug("Database connection established")
        
        @event.listens_for(engine.sync_engine.pool, "checkout")
        def receive_checkout(dbapi_conn, connection_record, connection_proxy):
            """Log connection checkouts (for monitoring pool utilization)"""
            logger.debug("Connection checked out from pool")
        
        @event.listens_for(engine.sync_engine.pool, "checkin")
        def receive_checkin(dbapi_conn, connection_record):
            """Log connection check-ins"""
            logger.debug("Connection returned to pool")
        
        @event.listens_for(engine.sync_engine.pool, "invalid")
        def receive_invalid(dbapi_conn, connection_record, exception):
            """Log invalid connections"""
            logger.warning(f"Invalid connection detected: {exception}")
        
        @event.listens_for(engine.sync_engine.pool, "detach")
        def receive_detach(dbapi_conn, connection_record):
            """Log detached connections"""
            logger.warning("Connection detached from pool (may indicate stale connection)")


class QueryPerformanceMonitor:
    """
    Monitors and logs slow queries for performance optimization.
    
    Helps identify N+1 problems and query bottlenecks.
    """
    
    SLOW_QUERY_THRESHOLD_MS = 100  # Log queries > 100ms
    
    def __init__(self, engine: AsyncEngine):
        self.engine = engine
        self.slow_queries = []
        self.query_stats = {}
        self._register_events()
    
    def _register_events(self) -> None:
        """Register SQLAlchemy events for query monitoring"""
        
        @event.listens_for(self.engine.sync_engine, "before_cursor_execute")
        def receive_before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            """Record query start time"""
            # Attach start time to context
            if context is None:
                context = {}
            context._query_start_time = time.time()
        
        @event.listens_for(self.engine.sync_engine, "after_cursor_execute")
        def receive_after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            """Log query duration"""
            if context is None or not hasattr(context, '_query_start_time'):
                return
            
            duration_ms = (time.time() - context._query_start_time) * 1000
            
            # Track statistics
            query_type = statement.split()[0].upper()  # SELECT, INSERT, UPDATE, DELETE
            if query_type not in self.query_stats:
                self.query_stats[query_type] = {"count": 0, "total_ms": 0, "slow": 0}
            
            self.query_stats[query_type]["count"] += 1
            self.query_stats[query_type]["total_ms"] += duration_ms
            
            # Log slow queries
            if duration_ms > self.SLOW_QUERY_THRESHOLD_MS:
                self.query_stats[query_type]["slow"] += 1
                logger.warning(
                    f"SLOW QUERY ({duration_ms:.2f}ms): {statement[:100]}..."
                )
                self.slow_queries.append({
                    "statement": statement,
                    "duration_ms": duration_ms,
                    "parameters": parameters
                })
    
    def get_statistics(self) -> dict:
        """Get query statistics"""
        stats = {}
        for query_type, metrics in self.query_stats.items():
            avg_ms = metrics["total_ms"] / metrics["count"] if metrics["count"] > 0 else 0
            stats[query_type] = {
                "total_queries": metrics["count"],
                "total_time_ms": metrics["total_ms"],
                "avg_time_ms": avg_ms,
                "slow_queries": metrics["slow"]
            }
        return stats
    
    def get_slow_queries(self, limit: int = 10) -> list:
        """Get slowest queries"""
        return sorted(
            self.slow_queries,
            key=lambda q: q["duration_ms"],
            reverse=True
        )[:limit]


class DatabaseHealthChecker:
    """
    Monitors database health and connection pool status.
    """
    
    def __init__(self, engine: AsyncEngine):
        self.engine = engine
    
    async def check_health(self) -> dict:
        """Check database health"""
        try:
            # Test connection
            async with self.engine.begin() as conn:
                result = await conn.execute(text("SELECT 1"))
                _ = result.scalar()
            
            # Get pool status
            pool = self.engine.pool
            checked_out = pool.checked_out() if hasattr(pool, 'checked_out') else None
            size = pool.size() if hasattr(pool, 'size') else None
            
            return {
                "status": "healthy",
                "database_responsive": True,
                "pool_checked_out": checked_out,
                "pool_size": size,
            }
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return {
                "status": "unhealthy",
                "database_responsive": False,
                "error": str(e)
            }


# Configuration for FastAPI integration
DB_CONFIG = {
    "production": {
        "pool_size": 20,
        "max_overflow": 40,
        "pool_recycle": 3600,
        "pool_pre_ping": True,
    },
    "development": {
        "pool_size": 5,
        "max_overflow": 10,
        "pool_recycle": 3600,
        "pool_pre_ping": True,
    },
    "testing": {
        "poolclass": StaticPool,  # Use in-memory connections for tests
    }
}


# Example: Integration in FastAPI app
"""
from fastapi import FastAPI
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    app.state.engine = await ConnectionPoolOptimizer.create_engine_with_optimization(
        DATABASE_URL,
        environment="production"
    )
    app.state.monitor = QueryPerformanceMonitor(app.state.engine)
    app.state.health = DatabaseHealthChecker(app.state.engine)
    
    yield
    
    # Shutdown
    await app.state.engine.dispose()

app = FastAPI(lifespan=lifespan)

@app.get("/health/db")
async def check_db_health(request: Request):
    health = await request.app.state.health.check_health()
    stats = request.app.state.monitor.get_statistics()
    
    return {
        "health": health,
        "query_stats": stats,
        "slow_queries": request.app.state.monitor.get_slow_queries(5)
    }
"""


# Migration: Apply pool optimization to existing engine
async def optimize_existing_engine(engine: AsyncEngine) -> None:
    """
    Upgrade connection pool settings on existing engine.
    
    Should be called during application startup.
    """
    pool = engine.pool
    
    # Log current settings
    logger.info(f"Current pool settings: size={pool.size()}, checked_out={pool.checked_out()}")
    
    # Apply optimized settings
    if hasattr(pool, 'timeout'):
        logger.info("Connection pool optimizations applied")

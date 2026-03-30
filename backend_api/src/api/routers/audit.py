"""
PUBLIC_INTERFACE
Audit router for audit event queries.
"""
from fastapi import APIRouter, HTTPException, Security, Query
from typing import Optional

from database import get_connection
from schemas import GetAuditEventsResponse, AuditEvent, ErrorResponse
from services.audit import AuditService
from services.auth import require_roles
from utils import make_error_response, generate_id

router = APIRouter(
    prefix="/api/v1/audit",
    tags=["audit"],
    responses={
        401: {"model": ErrorResponse, "description": "Authentication failed"},
        403: {"model": ErrorResponse, "description": "Authorization failed"},
        500: {"model": ErrorResponse, "description": "Internal server error"},
    },
)


@router.get(
    "/events",
    response_model=GetAuditEventsResponse,
    summary="Query audit events",
    description="Query audit events with optional filters. Restricted to auditor and governance_admin roles.",
    operation_id="query_audit_events",
    responses={
        200: {"description": "Audit events retrieved"},
        403: {"model": ErrorResponse, "description": "Insufficient permissions"},
    },
)
async def query_audit_events(
    entity_type: Optional[str] = Query(None, description="Filter by entity type"),
    entity_id: Optional[str] = Query(None, description="Filter by entity ID"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum events to return"),
    current_user: dict = Security(require_roles(["auditor", "admin", "governance_admin"])),
) -> GetAuditEventsResponse:
    """
    PUBLIC_INTERFACE
    Query audit events.

    Authentication: Bearer token required
    Authorization: auditor, governance_admin roles only
    """
    db = get_connection()

    try:
        audit_service = AuditService(db)
        events = audit_service.query_events(entity_type=entity_type, entity_id=entity_id, limit=limit)

        audit_events = [
            AuditEvent(
                audit_event_id=event["audit_event_id"],
                event_type=event["event_type"],
                entity_type=event["entity_type"],
                entity_id=event["entity_id"],
                actor_user_id=event["actor_user_id"],
                actor_role=event["actor_role"],
                timestamp_utc=event["timestamp_utc"],
                correlation_id=event["correlation_id"],
                result=event["result"],
                details_json=event.get("details_json"),
            )
            for event in events
        ]

        return GetAuditEventsResponse(events=audit_events)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=make_error_response(
                "INTERNAL_ERROR",
                f"Failed to query audit events: {str(e)}",
                generate_id("req"),
            ),
        )

"""
ORM models for annotation lineage identity tables (POL-652 / Schema A).

Tables:
    annotation_set     — groups annotations produced together (one run/batch).
    annotation_subject — stable target identity for what is being annotated.

These foundations are consumed by later phases:
    POL-653 (annotation_geometry), POL-654 (provenance/quality), POL-655 (export).
"""

from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    Index,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID

from .base import Base


class AnnotationSet(Base):
    """
    Groups annotations produced together: one human labeling batch,
    one model inference run, or one dataset import.

    Rows are immutable once created.  New annotation work produces a new set.

    The (source_name, source_version, run_id) partial unique index prevents
    importing the same run twice when run_id is provided.
    """

    __tablename__ = "annotation_set"

    set_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    name = Column(String(255))
    description = Column(Text)
    dataset = Column(String(64), nullable=False, server_default="ibrida")
    release = Column(String(16))
    source_kind = Column(String(32), nullable=False)
    source_name = Column(String(128), nullable=False)
    source_version = Column(String(64))
    model_id = Column(String(128))
    prompt_hash = Column(String(64))
    config_hash = Column(String(64))
    run_id = Column(String(128))
    created_by = Column(String(128))
    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "source_kind IN ('human', 'model', 'imported_dataset')",
            name="chk_source_kind",
        ),
        Index("idx_annotation_set_dataset_release", "dataset", "release"),
        Index("idx_annotation_set_source", "source_kind", "source_name"),
        Index("idx_annotation_set_created_at", "created_at"),
    )


class AnnotationSubject(Base):
    """
    Stable identity for the target of annotation: "what is being annotated."

    A subject always references an asset (image/video frame).  Optionally
    links to an observation and a frame/time range (for video assets).

    asset_uuid is intentionally NOT a FK to photos or media — it must
    work for both iNat photo_uuids and non-iNat media items.
    """

    __tablename__ = "annotation_subject"

    subject_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    asset_uuid = Column(UUID(as_uuid=True), nullable=False, index=True)
    observation_uuid = Column(UUID(as_uuid=True))
    frame_index = Column(Integer)
    time_start_ms = Column(Integer)
    time_end_ms = Column(Integer)
    asset_width_px = Column(Integer)
    asset_height_px = Column(Integer)
    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "time_end_ms IS NULL OR time_start_ms IS NULL "
            "OR time_end_ms >= time_start_ms",
            name="chk_time_range",
        ),
        CheckConstraint(
            "frame_index IS NULL OR frame_index >= 0",
            name="chk_frame_index",
        ),
        CheckConstraint(
            "(asset_width_px IS NULL OR asset_width_px > 0) "
            "AND (asset_height_px IS NULL OR asset_height_px > 0)",
            name="chk_dimensions",
        ),
        Index("idx_annotation_subject_created_at", "created_at"),
    )

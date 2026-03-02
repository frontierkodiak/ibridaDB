"""
ORM models for annotation lineage tables.

Schema A (POL-652):
    annotation_set     — groups annotations produced together (one run/batch).
    annotation_subject — stable target identity for what is being annotated.

Schema B (POL-653):
    annotation          — core annotation row (label, score, lifecycle).
    annotation_geometry — discriminated geometry (bbox/polygon/mask/point).

Schema C (POL-654):
    annotation_provenance — source completeness and lineage metadata per annotation.
    annotation_quality    — review/adjudication policy per annotation.
"""

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
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
        Index(
            "uq_annotation_set_run",
            "source_name",
            "source_version",
            "run_id",
            unique=True,
            postgresql_where=run_id.isnot(None),
        ),
        Index("idx_annotation_set_dataset_release", "dataset", "release"),
        Index("idx_annotation_set_source", "source_kind", "source_name"),
        Index("idx_annotation_set_created_at", "created_at"),
        Index(
            "idx_annotation_set_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
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
    asset_uuid = Column(UUID(as_uuid=True), nullable=False)
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
        Index(
            "uq_annotation_subject_asset_frame",
            asset_uuid,
            func.coalesce(frame_index, -1),
            func.coalesce(time_start_ms, -1),
            func.coalesce(time_end_ms, -1),
            unique=True,
        ),
        Index("idx_annotation_subject_asset", "asset_uuid"),
        Index(
            "idx_annotation_subject_observation",
            "observation_uuid",
            postgresql_where=observation_uuid.isnot(None),
        ),
        Index(
            "idx_annotation_subject_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
        Index("idx_annotation_subject_created_at", "created_at"),
    )


class Annotation(Base):
    """
    Core annotation row linking a subject ("what") to a set ("who/when/how").

    This row stores label/class information, optional model confidence, and a
    lifecycle marker for soft-versioning without destructive overwrite.
    """

    __tablename__ = "annotation"

    annotation_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    subject_id = Column(
        UUID(as_uuid=True),
        ForeignKey("annotation_subject.subject_id"),
        nullable=False,
    )
    set_id = Column(
        UUID(as_uuid=True),
        ForeignKey("annotation_set.set_id"),
        nullable=False,
    )
    label = Column(String(255), nullable=False)
    label_id = Column(Integer)
    taxon_id = Column(Integer)
    score = Column(Float)
    is_primary = Column(Boolean, nullable=False, server_default="false")
    lifecycle_state = Column(String(32), nullable=False, server_default="active")
    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "lifecycle_state IN ('active', 'superseded', 'retracted')",
            name="chk_annotation_lifecycle",
        ),
        CheckConstraint(
            "score IS NULL OR (score >= 0.0 AND score <= 1.0)",
            name="chk_annotation_score",
        ),
        Index("idx_annotation_subject_set", "subject_id", "set_id"),
        Index("idx_annotation_set_id", "set_id"),
        Index("idx_annotation_label", "label"),
        Index("idx_annotation_taxon", "taxon_id", postgresql_where=taxon_id.isnot(None)),
        Index(
            "idx_annotation_active",
            "subject_id",
            postgresql_where=lifecycle_state == "active",
        ),
        Index("idx_annotation_created_at", "created_at"),
        Index(
            "idx_annotation_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
    )


class AnnotationGeometry(Base):
    """
    Discriminated geometry payload for an annotation.

    Supports bbox, polygon, mask, and point representations without coercion.
    Canonical coordinate space is normalized [0,1] with top-left origin.
    """

    __tablename__ = "annotation_geometry"

    geometry_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    annotation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("annotation.annotation_id"),
        nullable=False,
    )
    geometry_kind = Column(String(16), nullable=False)

    # bbox (normalized)
    bbox_x_min = Column(Float)
    bbox_y_min = Column(Float)
    bbox_x_max = Column(Float)
    bbox_y_max = Column(Float)

    # bbox (pixel convenience)
    bbox_x_min_px = Column(Integer)
    bbox_y_min_px = Column(Integer)
    bbox_x_max_px = Column(Integer)
    bbox_y_max_px = Column(Integer)

    # polygon/mask/point payloads
    polygon_vertices = Column(JSONB)
    mask_rle = Column(JSONB)
    mask_uri = Column(Text)
    mask_format = Column(String(32))
    point_x = Column(Float)
    point_y = Column(Float)

    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "geometry_kind IN ('bbox', 'polygon', 'mask', 'point')",
            name="chk_geometry_kind",
        ),
        CheckConstraint(
            "bbox_x_min IS NULL OR bbox_x_max IS NULL "
            "OR (bbox_x_min < bbox_x_max AND bbox_y_min < bbox_y_max)",
            name="chk_bbox_ordering",
        ),
        CheckConstraint(
            "bbox_x_min IS NULL OR ("
            "bbox_x_min >= 0.0 AND bbox_x_min <= 1.0 "
            "AND bbox_y_min >= 0.0 AND bbox_y_min <= 1.0 "
            "AND bbox_x_max >= 0.0 AND bbox_x_max <= 1.0 "
            "AND bbox_y_max >= 0.0 AND bbox_y_max <= 1.0"
            ")",
            name="chk_bbox_normalized",
        ),
        CheckConstraint(
            "bbox_x_min_px IS NULL OR ("
            "bbox_x_min_px >= 0 AND bbox_y_min_px >= 0 "
            "AND bbox_x_max_px >= 0 AND bbox_y_max_px >= 0"
            ")",
            name="chk_bbox_px_nonneg",
        ),
        CheckConstraint(
            "point_x IS NULL OR ("
            "point_x >= 0.0 AND point_x <= 1.0 "
            "AND point_y >= 0.0 AND point_y <= 1.0"
            ")",
            name="chk_point_normalized",
        ),
        CheckConstraint(
            "geometry_kind != 'mask' OR mask_rle IS NOT NULL OR mask_uri IS NOT NULL",
            name="chk_mask_payload",
        ),
        CheckConstraint(
            "geometry_kind != 'bbox' OR ("
            "bbox_x_min IS NOT NULL AND bbox_y_min IS NOT NULL "
            "AND bbox_x_max IS NOT NULL AND bbox_y_max IS NOT NULL"
            ")",
            name="chk_bbox_complete",
        ),
        CheckConstraint(
            "geometry_kind != 'point' OR (point_x IS NOT NULL AND point_y IS NOT NULL)",
            name="chk_point_complete",
        ),
        CheckConstraint(
            "geometry_kind != 'polygon' OR polygon_vertices IS NOT NULL",
            name="chk_polygon_complete",
        ),
        Index("idx_geometry_annotation", "annotation_id"),
        Index("idx_geometry_kind", "geometry_kind"),
        Index("idx_geometry_annotation_kind", "annotation_id", "geometry_kind"),
        Index("idx_geometry_created_at", "created_at"),
        Index(
            "idx_geometry_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
        Index(
            "idx_geometry_polygon_vertices",
            "polygon_vertices",
            postgresql_using="gin",
            postgresql_where=polygon_vertices.isnot(None),
        ),
        Index(
            "idx_geometry_mask_rle",
            "mask_rle",
            postgresql_using="gin",
            postgresql_where=mask_rle.isnot(None),
        ),
    )


class AnnotationProvenance(Base):
    """
    Per-annotation provenance metadata.

    Source-kind-specific completeness guarantees:
    - human: operator_identity required
    - model: model_id + config_hash + run_id required
    - imported_dataset: source_version required
    """

    __tablename__ = "annotation_provenance"

    provenance_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    annotation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("annotation.annotation_id"),
        nullable=False,
    )

    source_kind = Column(String(32), nullable=False)
    source_name = Column(String(128), nullable=False)
    source_version = Column(String(64))

    model_id = Column(String(128))
    prompt_hash = Column(String(64))
    config_hash = Column(String(64))
    run_id = Column(String(128))

    operator_identity = Column(String(128))
    recorded_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "annotation_id",
            name="uq_annotation_provenance_annotation",
        ),
        CheckConstraint(
            "source_kind IN ('human', 'model', 'imported_dataset')",
            name="chk_provenance_source_kind",
        ),
        CheckConstraint(
            "prompt_hash IS NULL OR prompt_hash ~ '^[0-9a-f]{64}$'",
            name="chk_provenance_prompt_hash_hex",
        ),
        CheckConstraint(
            "config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$'",
            name="chk_provenance_config_hash_hex",
        ),
        CheckConstraint(
            "(source_kind = 'human' AND operator_identity IS NOT NULL) "
            "OR (source_kind = 'model' AND model_id IS NOT NULL AND config_hash IS NOT NULL AND run_id IS NOT NULL) "
            "OR (source_kind = 'imported_dataset' AND source_version IS NOT NULL)",
            name="chk_provenance_required_by_kind",
        ),
        Index(
            "idx_provenance_source",
            "source_kind",
            "source_name",
            "source_version",
        ),
        Index(
            "idx_provenance_model",
            "model_id",
            postgresql_where=model_id.isnot(None),
        ),
        Index(
            "idx_provenance_run_id",
            "run_id",
            postgresql_where=run_id.isnot(None),
        ),
        Index("idx_provenance_recorded_at", "recorded_at"),
        Index(
            "idx_provenance_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
    )


class AnnotationQuality(Base):
    """
    Per-annotation quality and adjudication metadata.

    Adjudicated states (accepted/rejected/conflict) require adjudicator identity
    and timestamp.
    """

    __tablename__ = "annotation_quality"

    quality_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    annotation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("annotation.annotation_id"),
        nullable=False,
    )

    review_status = Column(String(32), nullable=False, server_default="unreviewed")
    confidence_score = Column(Float)
    conflict_flag = Column(Boolean, nullable=False, server_default="false")
    conflict_reason = Column(Text)

    adjudicated_by = Column(String(128))
    adjudicated_at = Column(DateTime(timezone=True))
    review_notes = Column(Text)

    sidecar = Column(JSONB)
    created_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "annotation_id",
            name="uq_annotation_quality_annotation",
        ),
        CheckConstraint(
            "review_status IN ('unreviewed', 'needs_review', 'accepted', 'rejected', 'conflict')",
            name="chk_quality_review_status",
        ),
        CheckConstraint(
            "confidence_score IS NULL OR (confidence_score >= 0.0 AND confidence_score <= 1.0)",
            name="chk_quality_confidence_range",
        ),
        CheckConstraint(
            "("
            "review_status IN ('accepted', 'rejected', 'conflict') "
            "AND adjudicated_by IS NOT NULL "
            "AND adjudicated_at IS NOT NULL"
            ")"
            " OR "
            "("
            "review_status IN ('unreviewed', 'needs_review')"
            ")",
            name="chk_quality_adjudication_required",
        ),
        CheckConstraint(
            "(review_status = 'conflict' AND conflict_flag = TRUE) "
            "OR (review_status <> 'conflict')",
            name="chk_quality_conflict_consistency",
        ),
        CheckConstraint(
            "conflict_flag = FALSE OR conflict_reason IS NOT NULL",
            name="chk_quality_conflict_reason",
        ),
        Index("idx_quality_status", "review_status"),
        Index("idx_quality_status_conflict", "review_status", "conflict_flag"),
        Index(
            "idx_quality_confidence",
            "confidence_score",
            postgresql_where=confidence_score.isnot(None),
        ),
        Index(
            "idx_quality_adjudicated_at",
            "adjudicated_at",
            postgresql_where=adjudicated_at.isnot(None),
        ),
        Index(
            "idx_quality_sidecar",
            "sidecar",
            postgresql_using="gin",
            postgresql_where=sidecar.isnot(None),
        ),
    )

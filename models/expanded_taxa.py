from sqlalchemy import Boolean, Column, Float, Index, Integer, String
from .base import Base


class ExpandedTaxa(Base):
    """
    ORM model for the expanded_taxa table.
    
    This table provides a wide, denormalized view of taxonomic data with:
    - Core taxon information (ID, rank, names)
    - Immediate ancestor columns for efficient parent lookups
    - Full ancestral hierarchy columns (L* columns) for each taxonomic rank
    - Common names from Catalog of Life integration
    
    Immediate Ancestor Columns (Added 2025-05-26):
    - immediateAncestor_taxonID: Direct parent taxon, regardless of rank
    - immediateAncestor_rankLevel: Rank level of the immediate parent
    - immediateMajorAncestor_taxonID: Nearest ancestor at a major rank (multiple of 10)
    - immediateMajorAncestor_rankLevel: Rank level of the immediate major ancestor
    
    These columns enable O(1) parent lookups instead of scanning all L* columns.
    When immediate parent is already at a major rank, both sets of columns will have the same values.
    Root taxa (e.g., Animalia) will have NULL values for all ancestor columns.
    """
    __tablename__ = "expanded_taxa"

    taxonID = Column(Integer, primary_key=True, nullable=False)
    rankLevel = Column(Float, index=True)
    rank = Column(String(255))
    name = Column(String(255), index=True)
    commonName = Column(String(255))  # NEW - populated from ColDP integration
    taxonActive = Column(Boolean, index=True)
    
    # Immediate ancestor columns for efficient parent lookups # NEW
    immediateMajorAncestor_taxonID = Column(Integer, index=True)  # NEW
    immediateMajorAncestor_rankLevel = Column(Float)  # NEW
    immediateAncestor_taxonID = Column(Integer, index=True)  # NEW
    immediateAncestor_rankLevel = Column(Float)  # NEW

    # Ancestral columns
    # Each rank level has three columns: taxonID, name, and commonName
    # The commonName columns are NEW - populated from ColDP integration
    L5_taxonID = Column(Integer)
    L5_name = Column(String(255))
    L5_commonName = Column(String(255))  # NEW - from ColDP
    L10_taxonID = Column(Integer)
    L10_name = Column(String(255))
    L10_commonName = Column(String(255))  # NEW - from ColDP
    L11_taxonID = Column(Integer)
    L11_name = Column(String(255))
    L11_commonName = Column(String(255))  # NEW - from ColDP
    L12_taxonID = Column(Integer)
    L12_name = Column(String(255))
    L12_commonName = Column(String(255))  # NEW - from ColDP
    L13_taxonID = Column(Integer)
    L13_name = Column(String(255))
    L13_commonName = Column(String(255))  # NEW - from ColDP
    L15_taxonID = Column(Integer)
    L15_name = Column(String(255))
    L15_commonName = Column(String(255))  # NEW - from ColDP
    L20_taxonID = Column(Integer)
    L20_name = Column(String(255))
    L20_commonName = Column(String(255))  # NEW - from ColDP
    L24_taxonID = Column(Integer)
    L24_name = Column(String(255))
    L24_commonName = Column(String(255))  # NEW - from ColDP
    L25_taxonID = Column(Integer)
    L25_name = Column(String(255))
    L25_commonName = Column(String(255))  # NEW - from ColDP
    L26_taxonID = Column(Integer)
    L26_name = Column(String(255))
    L26_commonName = Column(String(255))  # NEW - from ColDP
    L27_taxonID = Column(Integer)
    L27_name = Column(String(255))
    L27_commonName = Column(String(255))  # NEW - from ColDP
    L30_taxonID = Column(Integer)
    L30_name = Column(String(255))
    L30_commonName = Column(String(255))  # NEW - from ColDP
    L32_taxonID = Column(Integer)
    L32_name = Column(String(255))
    L32_commonName = Column(String(255))  # NEW - from ColDP
    L33_taxonID = Column(Integer)
    L33_name = Column(String(255))
    L33_commonName = Column(String(255))  # NEW - from ColDP
    L33_5_taxonID = Column(Integer)
    L33_5_name = Column(String(255))
    L33_5_commonName = Column(String(255))  # NEW - from ColDP
    L34_taxonID = Column(Integer)
    L34_name = Column(String(255))
    L34_commonName = Column(String(255))  # NEW - from ColDP
    L34_5_taxonID = Column(Integer)
    L34_5_name = Column(String(255))
    L34_5_commonName = Column(String(255))  # NEW - from ColDP
    L35_taxonID = Column(Integer)
    L35_name = Column(String(255))
    L35_commonName = Column(String(255))  # NEW - from ColDP
    L37_taxonID = Column(Integer)
    L37_name = Column(String(255))
    L37_commonName = Column(String(255))  # NEW - from ColDP
    L40_taxonID = Column(Integer)
    L40_name = Column(String(255))
    L40_commonName = Column(String(255))  # NEW - from ColDP
    L43_taxonID = Column(Integer)
    L43_name = Column(String(255))
    L43_commonName = Column(String(255))  # NEW - from ColDP
    L44_taxonID = Column(Integer)
    L44_name = Column(String(255))
    L44_commonName = Column(String(255))  # NEW - from ColDP
    L45_taxonID = Column(Integer)
    L45_name = Column(String(255))
    L45_commonName = Column(String(255))  # NEW - from ColDP
    L47_taxonID = Column(Integer)
    L47_name = Column(String(255))
    L47_commonName = Column(String(255))  # NEW - from ColDP
    L50_taxonID = Column(Integer)
    L50_name = Column(String(255))
    L50_commonName = Column(String(255))  # NEW - from ColDP
    L53_taxonID = Column(Integer)
    L53_name = Column(String(255))
    L53_commonName = Column(String(255))  # NEW - from ColDP
    L57_taxonID = Column(Integer)
    L57_name = Column(String(255))
    L57_commonName = Column(String(255))  # NEW - from ColDP
    L60_taxonID = Column(Integer)
    L60_name = Column(String(255))
    L60_commonName = Column(String(255))  # NEW - from ColDP
    L67_taxonID = Column(Integer)
    L67_name = Column(String(255))
    L67_commonName = Column(String(255))  # NEW - from ColDP
    L70_taxonID = Column(Integer)
    L70_name = Column(String(255))
    L70_commonName = Column(String(255))  # NEW - from ColDP


# Important indexes for lookups
Index("idx_expanded_taxa_L10_taxonID", ExpandedTaxa.L10_taxonID)
Index("idx_immediate_ancestor_taxon_id", ExpandedTaxa.immediateAncestor_taxonID)  # NEW
Index("idx_immediate_major_ancestor_taxon_id", ExpandedTaxa.immediateMajorAncestor_taxonID)  # NEW

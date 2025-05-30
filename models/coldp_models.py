from sqlalchemy import (
    Column, String, Text, Boolean, Date, Numeric, Integer
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base

from .base import Base

class ColdpVernacularName(Base):
    __tablename__ = "coldp_vernacular_name"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    taxonID        = Column(String(64), index=True, nullable=False)
    sourceID       = Column(String(10))
    name           = Column(Text, nullable=False)
    transliteration= Column(Text)
    language       = Column(String(3))      # ISO‑639‑3
    preferred      = Column(Boolean)
    country        = Column(String(10))     # ISO‑3166‑1‑alpha‑2, increased size for data compatibility
    area           = Column(Text)
    sex            = Column(String(20))
    referenceID    = Column(String(64))
    remarks        = Column(Text)

class ColdpDistribution(Base):
    __tablename__ = "coldp_distribution"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    taxonID        = Column(String(64), index=True)
    sourceID       = Column(String(64))
    areaID         = Column(String(64))
    area           = Column(Text)
    gazetteer      = Column(String(64))
    status         = Column(String(64))     # e.g. native, introduced
    referenceID    = Column(String(64))
    remarks        = Column(Text)

class ColdpMedia(Base):
    __tablename__ = "coldp_media"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    taxonID        = Column(String(64), index=True)
    sourceID       = Column(String(64))
    url            = Column(Text, nullable=False)
    type           = Column(String(64))     # stillImage, sound, video …
    format         = Column(String(64))     # MIME type or file suffix
    title          = Column(Text)
    created        = Column(Date)
    creator        = Column(Text)
    license        = Column(String(128))
    link           = Column(Text)           # landing page
    remarks        = Column(Text)

class ColdpReference(Base):
    __tablename__ = "coldp_reference"
    ID             = Column(String(255), primary_key=True)   # UUID or short key
    alternativeID  = Column(Text)
    sourceID       = Column(Text)
    citation       = Column(Text)
    type           = Column(Text)
    author         = Column(Text)
    editor         = Column(Text)
    title          = Column(Text)
    titleShort     = Column(Text)
    containerAuthor= Column(Text)
    containerTitle = Column(Text)
    containerTitleShort = Column(Text)
    issued         = Column(Text)
    accessed       = Column(Text)
    collectionTitle= Column(Text)
    collectionEditor= Column(Text)
    volume         = Column(Text)
    issue          = Column(Text)
    edition        = Column(Text)
    page           = Column(Text)
    publisher      = Column(Text)
    publisherPlace = Column(Text)
    version        = Column(Text)
    isbn           = Column(Text)
    issn           = Column(Text)
    doi            = Column(Text)
    link           = Column(Text)
    remarks        = Column(Text)

class ColdpTypeMaterial(Base):
    """
    ColDP entity `TypeMaterial` (called TypeSpecimen in the user request).
    """
    __tablename__ = "coldp_type_material"
    ID              = Column(String(64), primary_key=True)
    nameID          = Column(String(64), index=True)
    sourceID        = Column(String(64))
    citation        = Column(Text)
    status          = Column(String(64))
    referenceID     = Column(String(64))
    page            = Column(String(64))
    country         = Column(String(10))
    locality        = Column(Text)
    latitude        = Column(Numeric(9,5))
    longitude       = Column(Numeric(9,5))
    altitude        = Column(String(64))
    sex             = Column(String(20))
    host            = Column(Text)
    associatedSequences = Column(Text)
    date            = Column(Date)
    collector       = Column(Text)
    institutionCode = Column(String(64))
    catalogNumber   = Column(String(64))
    link            = Column(Text)
    remarks         = Column(Text)

# ColdpNameUsage class for staging with all the necessary fields for mapping
class ColdpNameUsage(Base):
    """
    Represents the ColDP NameUsage.tsv table with fields needed for mapping to iNaturalist taxa.
    
    This model includes fields needed for:
    1. Basic identification and matching (ID, scientificName, rank, status)
    2. Taxonomic hierarchy fields for resolving homonyms during fuzzy matching
    3. Name components for more detailed matching
    """
    __tablename__ = "coldp_name_usage_staging"
    ID = Column(String(64), primary_key=True)
    
    # Basic identification
    scientificName = Column(Text, index=True)
    authorship = Column(Text)
    rank = Column(String(64), index=True)
    status = Column(String(64), index=True)
    parentID = Column(String(64))
    
    # Name components
    uninomial = Column(Text)  # For genus or higher rank names
    genericName = Column(Text)  # Note: ColDP uses 'genus' for genus part of binomial
    infragenericEpithet = Column(Text)
    specificEpithet = Column(Text)
    infraspecificEpithet = Column(Text)
    basionymID = Column(String(64))
    
    # Taxonomic hierarchy fields for homonym resolution
    # These simplify matching across taxonomic hierarchies
    # In ColDP NameUsage they appear at the end of the TSV
    family = Column(Text)
    order = Column(Text) 
    class_ = Column(Text)  # Using class_ to avoid Python keyword conflict
    phylum = Column(Text)
    kingdom = Column(Text)
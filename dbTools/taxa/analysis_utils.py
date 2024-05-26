from ibridaDB.schema import Observations, Taxa, TaxaTemp

def count_new_taxa(session, taxon_id):
    return session.query(TaxaTemp).filter(TaxaTemp.taxon_id == taxon_id, ~session.query(Taxa).filter(Taxa.taxon_id == taxon_id).exists()).count()

def count_deprecated_taxa(session, taxon_id):
    return session.query(Taxa).filter(Taxa.taxon_id == taxon_id, ~session.query(TaxaTemp).filter(TaxaTemp.taxon_id == taxon_id).exists()).count()

def count_active_status_changes(session, taxon_id):
    return session.query(Taxa, TaxaTemp).filter(
        Taxa.taxon_id == taxon_id,
        TaxaTemp.taxon_id == taxon_id,
        Taxa.active != TaxaTemp.active
    ).count()

def count_name_changes(session, taxon_id):
    return session.query(Taxa, TaxaTemp).filter(
        Taxa.taxon_id == taxon_id,
        TaxaTemp.taxon_id == taxon_id,
        Taxa.name != TaxaTemp.name
    ).count()

def count_other_attribute_changes(session, taxon_id):
    return session.query(Taxa, TaxaTemp).filter(
        Taxa.taxon_id == taxon_id,
        TaxaTemp.taxon_id == taxon_id,
        (Taxa.ancestry != TaxaTemp.ancestry) |
        (Taxa.rank_level != TaxaTemp.rank_level) |
        (Taxa.rank != TaxaTemp.rank)
    ).count()

def count_observations_for_taxa(session, taxon_id, category):
    if category == 'new':
        return session.query(Observations).join(TaxaTemp, Observations.taxon_id == TaxaTemp.taxon_id).filter(
            TaxaTemp.taxon_id == taxon_id,
            ~session.query(Taxa).filter(Taxa.taxon_id == taxon_id).exists()
        ).count()
    elif category == 'deprecated':
        return session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).filter(
            Taxa.taxon_id == taxon_id,
            ~session.query(TaxaTemp).filter(TaxaTemp.taxon_id == taxon_id).exists()
        ).count()
    elif category == 'active_status_changes':
        return session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).join(TaxaTemp, Taxa.taxon_id == TaxaTemp.taxon_id).filter(
            Taxa.taxon_id == taxon_id,
            Taxa.active != TaxaTemp.active
        ).count()

def count_observations_for_common_taxa(session, taxon_id, category):
    if category == 'new':
        return session.query(Observations).join(TaxaTemp, Observations.taxon_id == TaxaTemp.taxon_id).filter(
            TaxaTemp.taxon_id == taxon_id,
            ~session.query(Taxa).filter(Taxa.taxon_id == taxon_id).exists(),
            session.query(Observations).filter(Observations.taxon_id == TaxaTemp.taxon_id).count() > 180
        ).count()
    elif category == 'deprecated':
        return session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).filter(
            Taxa.taxon_id == taxon_id,
            ~session.query(TaxaTemp).filter(TaxaTemp.taxon_id == taxon_id).exists(),
            session.query(Observations).filter(Observations.taxon_id == Taxa.taxon_id).count() > 180
        ).count()
    elif category == 'active_status_changes':
        return session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).join(TaxaTemp, Taxa.taxon_id == TaxaTemp.taxon_id).filter(
            Taxa.taxon_id == taxon_id,
            Taxa.active != TaxaTemp.active,
            session.query(Observations).filter(Observations.taxon_id == Taxa.taxon_id).count() > 180
        ).count()
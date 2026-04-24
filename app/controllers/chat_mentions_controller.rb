class ChatMentionsController < ApplicationController
  LIMIT_PER_TYPE = 6

  def index
    query = params[:q].to_s.strip.downcase

    accounts = Current.family.accounts.visible
    categories = Current.family.categories
    merchants = Current.family.merchants

    if query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      accounts = accounts.where("LOWER(name) LIKE ?", like)
      categories = categories.where("LOWER(name) LIKE ?", like)
      merchants = merchants.where("LOWER(name) LIKE ?", like)
    end

    results = []

    accounts.order(:name).limit(LIMIT_PER_TYPE).each do |a|
      results << { type: "account", id: a.id, name: a.name, subtitle: a.accountable_type }
    end

    categories.order(:name).limit(LIMIT_PER_TYPE).each do |c|
      results << { type: "category", id: c.id, name: c.name, subtitle: "Category", color: c.color }
    end

    merchants.order(:name).limit(LIMIT_PER_TYPE).each do |m|
      results << { type: "merchant", id: m.id, name: m.name, subtitle: "Merchant" }
    end

    render json: results
  end
end

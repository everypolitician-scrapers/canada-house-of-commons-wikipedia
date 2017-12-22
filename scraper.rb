#!/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require_relative 'lib/remove_notes'
require_relative 'lib/unspan_all_tables'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

PARTIES = {
  'Conservative'             => 'conservative',
  'Liberal'                  => 'liberal',
  'NDP'                      => 'ndp',
  'Bloc Québécois'           => 'bloc_québécois',
  'Green'                    => 'green_party',
  'FD'                       => 'forces_et_démocratie',
  'Independent'              => 'independent',
  'Independent Conservative' => 'independent_conservative',
  'Strength in Democracy'    => 'strength_in_democracy',
}.freeze

class MembersPage < Scraped::HTML
  decorator RemoveNotes
  decorator WikidataIdsDecorator::Links
  decorator UnspanAllTables

  field :members do
    members_tables.xpath('.//tr[td]').map { |tr| fragment(tr => MemberRow) }.reject(&:vacant?)
  end

  private

  def members_tables
    noko.xpath('//table[.//tr[th[.="Electoral district"]]]')
  end
end

class MemberRow < Scraped::HTML
  def vacant?
    tds[1].text == 'Vacant'
  end

  field :name do
    tds[1].at_css('a').text unless vacant?
  end

  field :id do
    tds[1].css('a/@wikidata').text
  end

  field :wikiname do
    tds[1].xpath('.//a[not(@class="new")]/@title').text
  end

  field :party do
    tds[2].text.tidy
  end

  field :district do
    district
  end

  field :state do
    noko.xpath('preceding::h3/span[@class="mw-headline"]').last.text
  end

  field :district do
    tds[3].text.tidy
  end

  field :district_id do
    tds[3].css('a/@wikidata').text
  end

  field :area do
    '%s (%s)' % [state, district]
  end

  field :term do
    url[/members_of_the_(\d+)[snrt][tdh]_Parliament/, 1]
  end

  field :source do
    url
  end

  field :party_id do
    PARTIES[party] || raise("No such party: #{party}")
  end

  field :start_date do
    tds[0..2].map do |td|
      if matched = td.text.match(/since (.*)/) || td.text.match(/after (.*)/)
        date_from(matched.captures.first)
      end
    end.compact.first
  end

  field :end_date do
    tds[0..2].map do |td|
      if matched = td.text.match(/until (.*)/)
        date_from(matched.captures.first)
      end
    end.compact.first
  end

  private

  def tds
    noko.css('td')
  end

  def date_from(str)
    return if str.to_s.empty?
    Date.parse(str).to_s rescue nil
  end
end

terms = [
  'https://en.wikipedia.org/wiki/List_of_House_members_of_the_42nd_Parliament_of_Canada',
  'https://en.wikipedia.org/wiki/List_of_House_members_of_the_41st_Parliament_of_Canada',
]

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
terms.each do |url|
  page = MembersPage.new(response: Scraped::Request.new(url: url).response)
  data = page.members.map(&:to_h)
  data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']
  ScraperWiki.save_sqlite(%i[wikiname term], data)
end

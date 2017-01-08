#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'nokogiri'
require 'pry'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

require_relative 'lib/unspanned_table'

class String
  def tidy
    gsub(/[[:space:]]+/, ' ').strip
  end
end

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

def noko_for(url)
  Nokogiri::HTML(open(URI.escape(URI.unescape(url))).read)
end

def date_from(str)
  return if str.to_s.empty?
  Date.parse(str).to_s rescue nil
end

def scrape_term(id, url)
  noko = noko_for(url)
  district = nil
  skip = 0

  noko.xpath('//table[.//tr[th[.="Electoral district"]]]').each do |table|
    unspanned = UnspannedTable.new(table).transformed

    unspanned.xpath('.//tr[td]').each do |tr|
      tds = tr.css('td')
      next if tds[1].text == 'Vacant'

      state = table.xpath('preceding::h3/span[@class="mw-headline"]').last.text
      district = tds[3].text.tidy

      data = {
        name:     tds[1].at_css('a').text,
        wikiname: tds[1].xpath('.//a[not(@class="new")]/@title').text,
        party:    tds[2].children.map(&:text).map(&:tidy).reject(&:empty?).first,
        state:    state,
        district: district,
        area:     '%s (%s)' % [state, district],
        term:     id,
        source:   url,
      }
      data[:party_id] = PARTIES[data[:party]] || raise("No such party: #{data[:party]}")

      if matched = tds[1].text.match(/until (.*)/)
        data[:start_date] = date_from(matched.captures.first)
      end
      if matched = tds[1].text.match(/after (.*)/)
        data[:end_date] = date_from(matched.captures.first)
      end

      ScraperWiki.save_sqlite(%i(wikiname term), data)
    end
  end
end

terms = {
  '42' => 'https://en.wikipedia.org/wiki/List_of_House_members_of_the_42nd_Parliament_of_Canada',
  '41' => 'https://en.wikipedia.org/wiki/List_of_House_members_of_the_41st_Parliament_of_Canada',
}

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
terms.each do |id, url|
  scrape_term(id, url)
end

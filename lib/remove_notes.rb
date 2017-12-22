# frozen_string_literal: true

require 'scraped'

class RemoveNotes < Scraped::Response::Decorator
  def body
    Nokogiri::HTML(super).tap do |doc|
      doc.css('sup.reference').remove
    end.to_s
  end
end

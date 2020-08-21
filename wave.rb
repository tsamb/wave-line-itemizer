require 'faraday'
require 'json'
require 'dotenv'

Dotenv.load


module Wave
  QUERY = <<~HEREDOC
    query($businessId: ID!, $page: Int!, $pageSize: Int!) {
      business(id: $businessId) {
        id
        isClassicInvoicing
        invoices(page: $page, pageSize: $pageSize) {
          pageInfo {
            currentPage
            totalPages
            totalCount
          }
          edges {
            node {
              createdAt
              invoiceNumber
              invoiceDate
              customer {
                name
              }
              dueDate
              total {
                value
              }
              items {
                product {
                  id
                  name
                }
                quantity
                price
              }
            }
          }
        }
      }
    }
  HEREDOC

  BUSINESS_ID = ENV["WAVE_BUSINESS_ID"]
  PAGE_SIZE = 50

  class << self
    def get_invoices(page: 1)
      url = 'https://gql.waveapps.com/graphql/public'
      body = {
        query: QUERY,
        variables: {
          "businessId" => BUSINESS_ID,
          "page" => page,
          "pageSize" => PAGE_SIZE
        }
      }.to_json
      resp = Faraday.post(url, body, {'Authorization' => "Bearer #{ENV["WAVE_KEY"]}",'Content-Type' => 'application/json'})
      JSON.parse(resp.body)
    end

    def get_all_invoices
      page_1 = get_invoices

      page_info = page_1.dig('data','business', 'invoices', 'pageInfo')
      page_count = page_info.dig('totalPages')
      total_invoices = page_info.dig('totalCount')

      puts "Fetched 1 of #{ page_count } pages (#{PAGE_SIZE}/#{total_invoices} invoices total)"

      pages = [page_1]

      if page_count > 1
        (2..page_count).each do |page_number|
          pages << get_invoices(page: page_number)
          puts "Fetched #{page_number} of #{ page_count } pages (#{ page_number == page_count ? total_invoices : page_number * PAGE_SIZE}/#{total_invoices} invoices total)"
        end
      end
      pages.map { |page| page.dig('data', 'business', 'invoices', 'edges') }.flatten.map { |node| node.dig('node') }
    end

    def denormalize(invoices)
      invoices.reduce([]) do |line_items, invoice|
        invoice.dig('items').each do |item|
          line_items << {
            "Product" => item.dig('product', 'name'),
            "Bottles sold" => item.dig('quantity'),
            "Price" => item.dig('price'),
            "Customer" => invoice.dig('customer', 'name'),
            "Invoice #" => invoice.dig('invoiceNumber'),
            "Invoice date" => invoice.dig('invoiceDate'),
            "Invoice created" => invoice.dig('createdAt'),
          }
        end
        line_items
      end
    end

    def get_line_items
      denormalize(get_all_invoices)
    end
  end
end

require 'pry'; binding.pry
puts "done"

require 'faraday'
require 'json'
require 'dotenv'
require 'csv'

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
              shippingDetails {
                address {
                  postalCode
                }
              }
              address {
                addressLine1
                addressLine2
                city
                postalCode
              }
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
              taxes {
                amount {
                  value
                }
                salesTax {
                  id
                  name
                }
              }
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
          raise "More than one tax on invoice # #{invoice.dig('invoiceNumber')}" unless item.dig("taxes").size <= 1
          line_items << {
            "Product" => item.dig('product', 'name'),
            "Invoice date" => invoice.dig('invoiceDate'),
            "Bottles sold" => item.dig('quantity'),
            "Price" => item.dig('price'),
            "Customer" => invoice.dig('customer', 'name'),
            "Invoice #" => invoice.dig('invoiceNumber'),
            "Invoice created" => invoice.dig('createdAt'),
            "Sales tax amount" => item.dig("taxes", 0, "amount", "value"),
            "Sales tax county" => item.dig("taxes", 0, "salesTax", "name"),
            "Customer zip" => invoice.dig('customer', 'address', 'postalCode'),
            "Shipping zip" => invoice.dig('customer', 'shippingDetails', 'address', 'postalCode'),
            "Customer address line 1" => invoice.dig('customer', 'address', 'addressLine1'),
            "Customer address line 2" => invoice.dig('customer', 'address', 'addressLine2'),
            "Customer city" => invoice.dig('customer', 'address', 'city'),
          }
        end
        line_items
      end
    end

    def get_line_items
      denormalize(get_all_invoices)
    end

    def build_csv
      name = "tax-sales-#{Time.now.strftime("%Y-%m-%d")}.csv"
      line_items = get_line_items.sort_by { |li| li['Invoice date'] }
      rows = 0
      CSV.open(name, 'wb') do |csv|
        csv << line_items.first.keys;
        line_items.each do |li|
          csv << li.values; rows += 1
        end
      end
      puts "#{rows} #{rows == 1 ? 'row' : 'rows'} written to #{name}"
    end
  end
end

Wave.build_csv

puts "done"

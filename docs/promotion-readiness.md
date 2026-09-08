# Promotion readiness and demand capacity

Sellora evaluates each product as **Promote**, **Limit**, or **Block** before a merchant features it or sends paid traffic to it. The decision is a planning aid; Sellora does not launch social campaigns.

## Inputs

- consented Shopify Web Pixel product views, cart activity, and checkout activity from the last 7 days
- paid Shopify order lines and cancellation, refund, fulfillment, and COD gateway labels from the last 30 days
- current inventory by variant, including size or option labels
- Shopify variant selling price and unit cost
- merchant assumptions for target ROAS, target acquisition cost, shipping, COD failure, runway, margin, and minimum useful order capacity

The planner refreshes after catalog and order sync jobs, during a full discovery run, when assumptions change, and when a merchant chooses **Refresh decisions**.

## Demand-weighted capacity

Variant demand uses an explainable weighted mix:

| Signal | Weight |
| --- | ---: |
| Product view | 1 |
| Cart add | 3 |
| Checkout started | 4 |
| Checkout completed | 6 |
| Paid unit | 8 |

Each variant's weighted signals become its share of product demand. Its order capacity is current inventory divided by that share. The product's safe order capacity is the lowest variant capacity, so a large quantity in unpopular sizes cannot conceal a depleted popular size. With no observed demand, Sellora uses equal variant shares and lowers confidence.

## Economics and limits

The contribution estimate subtracts unit cost, shipping, and expected COD failure cost from average selling price. Sellora withholds the promotion-spend ceiling if a demanded variant lacks a positive unit cost.

The spend ceiling is the lowest of:

- demand capacity × average selling price ÷ target ROAS
- demand capacity × estimated contribution per order
- demand capacity × target acquisition cost, when supplied

A product is blocked when it has no stock, a popular demanded variant is out of stock, safe capacity is below the merchant minimum, or estimated contribution is zero or negative. It is limited for low size coverage, short or unknown runway, missing economics, low margin, cancellations, or refunds. Other products with a stronger current score can be shown as safer substitutes.

The readiness score starts at 100 and applies visible reasons for those constraints. High confidence requires at least five paid units, five storefront events, and complete costs for demanded variants. Sparse or fallback evidence lowers confidence.

## COD limitation

Shopify's order and fulfillment labels do not prove courier delivery or COD cash collection. Sellora uses the recorded COD gateway share and the merchant's expected failure assumption for planning, and labels Shopify fulfillment only as a proxy. Courier reconciliation is required before Sellora can report delivered profit or actual COD collection.

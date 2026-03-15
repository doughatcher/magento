import { test, expect } from '@playwright/test';

/**
 * Magento Checkout E2E Test
 *
 * Tests the full storefront checkout flow with a simple product:
 * 1. Search for a product and add to cart
 * 2. Proceed to checkout
 * 3. Fill shipping information (guest checkout)
 * 4. Wait for and select shipping method
 * 5. Select Check/Money Order payment
 * 6. Place order
 * 7. Verify order confirmation
 *
 * This test was validated against Luma sample data storefronts.
 * It targets simple products to avoid configurable product complexity
 * (swatch selection, option dropdowns) which is fragile in CI.
 *
 * Environment variables:
 *   PLAYWRIGHT_BASE_URL — Magento storefront URL (default: https://localhost:8443)
 */

test.describe('Checkout Flow', () => {
  test('add simple product to cart and complete guest checkout', async ({ page }) => {
    // 1. Navigate to the storefront and search for a product
    await page.goto('/');
    await page.screenshot({ path: 'test-results/screenshots/01-homepage.png' });

    // Search for "backpack" — these are simple products in Luma sample data
    await page.fill('#search', 'backpack');
    await page.press('#search', 'Enter');
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'test-results/screenshots/02-search-results.png' });

    // 2. Click the first product from search results
    const productLink = page.locator('.product-item-link').first();
    await expect(productLink).toBeVisible({ timeout: 10000 });
    const productName = (await productLink.textContent())?.trim();
    console.log(`Selected product: ${productName}`);
    await productLink.click();
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'test-results/screenshots/03-product-page.png' });

    // 3. Handle product options if this is a configurable product
    // Select first option for any swatch attributes (color, size, etc.)
    const swatchAttributes = page.locator('.swatch-attribute');
    const swatchCount = await swatchAttributes.count();
    if (swatchCount > 0) {
      console.log(`Found ${swatchCount} swatch attribute(s) — selecting first option for each`);
      for (let i = 0; i < swatchCount; i++) {
        const firstOption = swatchAttributes.nth(i).locator('.swatch-option:not(.disabled)').first();
        if (await firstOption.isVisible()) {
          await firstOption.click();
          await page.waitForTimeout(500);
        }
      }
    }

    // Handle select dropdowns for configurable options
    const configSelects = page.locator('select.super-attribute-select');
    const selectCount = await configSelects.count();
    if (selectCount > 0) {
      console.log(`Found ${selectCount} config select(s) — selecting first option for each`);
      for (let i = 0; i < selectCount; i++) {
        const select = configSelects.nth(i);
        const options = select.locator('option:not([value=""])');
        if (await options.count() > 0) {
          const firstValue = await options.first().getAttribute('value');
          if (firstValue) await select.selectOption(firstValue);
        }
      }
    }

    // Add to cart
    const addToCartButton = page.locator('#product-addtocart-button');
    await expect(addToCartButton).toBeVisible();
    await addToCartButton.click();
    await page.waitForSelector('.message-success', { timeout: 15000 });
    console.log('Product added to cart');

    // 4. Go to checkout
    await page.goto('/checkout');
    await page.waitForLoadState('networkidle');
    // Wait for checkout JS to fully initialize
    await page.waitForSelector('#customer-email', { timeout: 30000 });
    await page.screenshot({ path: 'test-results/screenshots/04-checkout-shipping.png' });

    // 5. Fill guest shipping information
    // Set country FIRST so state/region dropdown populates correctly
    const countrySelect = page.locator('select[name="country_id"]');
    if (await countrySelect.isVisible()) {
      await countrySelect.selectOption('US');
      await page.waitForTimeout(1000);
    }

    await page.fill('#customer-email', 'e2e-test@example.com');

    // Small delay for email validation / login check to complete
    await page.waitForTimeout(2000);

    await page.fill('input[name="firstname"]', 'E2E');
    await page.fill('input[name="lastname"]', 'TestUser');
    await page.fill('input[name="street[0]"]', '123 Test Street');
    await page.fill('input[name="city"]', 'Los Angeles');

    // Select state
    const regionSelect = page.locator('select[name="region_id"]');
    if (await regionSelect.isVisible()) {
      await regionSelect.selectOption({ label: 'California' });
    }

    await page.fill('input[name="postcode"]', '90210');
    await page.fill('input[name="telephone"]', '5551234567');

    // 6. Wait for shipping methods to load after address is complete
    // Magento fires AJAX to estimate shipping after address fields change.
    // Radio buttons become temporarily disabled during recalculation.
    // The "no quotes available" message can flash transiently during AJAX —
    // we must wait for rates to fully resolve before checking.
    console.log('Waiting for shipping rates to load...');

    // Wait for shipping rate AJAX to complete — look for either radio buttons
    // or a stable "no quotes" message. The waitForFunction polls the DOM.
    const shippingResolved = await page.waitForFunction(() => {
      // Check if loading spinner is gone
      const loader = document.querySelector('.checkout-shipping-method .loading-mask');
      if (loader && (loader as HTMLElement).style.display !== 'none') return false;

      // Check if shipping radio buttons appeared
      const radios = document.querySelectorAll<HTMLInputElement>(
        '.table-checkout-shipping-method input[type="radio"]'
      );
      if (radios.length > 0 && Array.from(radios).some(r => !r.disabled)) {
        return 'rates';
      }

      // Check for stable "no quotes" message (only after loader is gone)
      const noQuotes = document.querySelector('.no-quotes-block');
      if (noQuotes) return 'no-quotes';

      // Also check text content as fallback
      const shippingSection = document.querySelector('#checkout-shipping-method-load');
      if (shippingSection?.textContent?.includes('no quotes are available')) {
        return 'no-quotes';
      }

      return false;
    }, { timeout: 30000 }).catch(() => null);

    const result = shippingResolved ? await shippingResolved.jsonValue() : null;

    if (result === 'no-quotes' || result === null) {
      await page.screenshot({ path: 'test-results/screenshots/05-no-shipping-quotes.png' });
      throw new Error(
        'No shipping quotes available for this address. ' +
        'Ensure shipping methods (Flat Rate, Free Shipping, etc.) are enabled in ' +
        'Magento admin: Stores > Configuration > Sales > Shipping Methods'
      );
    }

    console.log('Shipping rates loaded');
    const shippingRadio = page.locator('.table-checkout-shipping-method input[type="radio"]').first();
    await shippingRadio.check({ force: true });
    console.log('Shipping method selected');

    await page.screenshot({ path: 'test-results/screenshots/05-shipping-filled.png' });

    // 7. Continue to payment step
    const continueButton = page.locator('button[data-role="opc-continue"], button.continue');
    await expect(continueButton).toBeVisible({ timeout: 10000 });
    await continueButton.click();

    // Wait for payment step to load
    await page.waitForSelector('.payment-method', { timeout: 15000 });
    await page.waitForLoadState('networkidle');

    // Select Check/Money Order payment if multiple methods are available
    const checkmoRadio = page.locator('input#checkmo');
    if (await checkmoRadio.isVisible()) {
      await checkmoRadio.check({ force: true });
    }

    await page.screenshot({ path: 'test-results/screenshots/06-payment-step.png' });

    // 8. Place order
    const placeOrderButton = page.locator('button[title="Place Order"], button.action.primary.checkout');
    await expect(placeOrderButton).toBeVisible({ timeout: 15000 });
    await placeOrderButton.click();

    // 9. Verify order confirmation
    await page.waitForURL(/checkout\/onepage\/success/, { timeout: 30000 });
    const successContent = page.locator('.checkout-success, .page-title');
    await expect(successContent).toBeVisible({ timeout: 10000 });
    await page.screenshot({ path: 'test-results/screenshots/07-order-confirmation.png' });

    // Capture and log the order number
    const orderNumber = await page.locator('.order-number strong, .checkout-success p a').textContent();
    console.log(`Order placed successfully: ${orderNumber?.trim()}`);
  });
});

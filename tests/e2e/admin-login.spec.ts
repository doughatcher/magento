import { test, expect } from '@playwright/test';

/**
 * Magento Admin Login E2E Test
 *
 * Tests admin panel access:
 * 1. Navigate to admin login
 * 2. Login with credentials
 * 3. Verify dashboard loads
 *
 * Environment variables:
 *   PLAYWRIGHT_BASE_URL  — Magento storefront URL (default: https://localhost:8443)
 *   MAGENTO_ADMIN_URI    — Admin URI path (default: /backend)
 *   MAGENTO_ADMIN_USER   — Admin username (required in CI)
 *   MAGENTO_ADMIN_PASS   — Admin password (required in CI)
 */

test.describe('Admin Panel', () => {
  test('login to admin dashboard', async ({ page }) => {
    const adminUri = process.env.MAGENTO_ADMIN_URI || '/backend';
    const adminUser = process.env.MAGENTO_ADMIN_USER;
    const adminPass = process.env.MAGENTO_ADMIN_PASS;

    // Skip if credentials are not provided
    test.skip(!adminUser || !adminPass, 'MAGENTO_ADMIN_USER and MAGENTO_ADMIN_PASS must be set');

    // 1. Navigate to admin login
    await page.goto(adminUri);
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'test-results/screenshots/admin-01-login-page.png' });

    // 2. Fill credentials and login
    await page.fill('#username', adminUser!);
    await page.fill('#login', adminPass!);
    await page.screenshot({ path: 'test-results/screenshots/admin-02-credentials-filled.png' });

    await page.click('.action-login');
    await page.waitForURL(`**${adminUri}/admin/dashboard/**`, { timeout: 30000 });
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: 'test-results/screenshots/admin-03-dashboard.png' });

    // 3. Verify dashboard loaded
    await expect(page.locator('.page-title, .dashboard-title')).toBeVisible();
    console.log('Admin login successful — dashboard loaded');
  });
});

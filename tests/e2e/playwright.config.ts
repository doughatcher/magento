import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 120_000,
  retries: 1,
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'https://localhost:8443',
    ignoreHTTPSErrors: true,
    screenshot: 'on',
    trace: 'on-first-retry',
    headless: true,
    viewport: { width: 1280, height: 720 },
  },
  reporter: [
    ['html', { open: 'never', outputFolder: 'playwright-report' }],
    ['list'],
  ],
  outputDir: 'test-results',
});

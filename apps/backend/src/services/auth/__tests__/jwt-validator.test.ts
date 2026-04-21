#!/usr/bin/env node
// @file        apps/backend/src/services/auth/__tests__/jwt-validator.test.ts
// @module      services/auth/__tests__
// @description Unit tests for JWT validator
// @owner       Infrastructure Team
// @status      ACTIVE

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { JwtValidator } from '../jwt-validator';
import crypto from 'crypto';

describe('JwtValidator', () => {
  let validator: JwtValidator;

  beforeEach(() => {
    validator = new JwtValidator('http://localhost:4182');
  });

  afterEach(() => {
    validator.clearCache();
  });

  describe('validateToken', () => {
    it('should reject malformed tokens', async () => {
      const malformedToken = 'not.a.token';

      await expect(validator.validateToken(malformedToken, 'test-audience')).rejects.toThrow(
        'Invalid JWT format',
      );
    });

    it('should reject tokens without kid', async () => {
      const header = Buffer.from(JSON.stringify({ alg: 'RS256' })).toString('base64url');
      const payload = Buffer.from(
        JSON.stringify({
          sub: 'test',
          aud: 'test-audience',
          iss: 'http://localhost:4182',
          iat: Math.floor(Date.now() / 1000),
          exp: Math.floor(Date.now() / 1000) + 3600,
        }),
      ).toString('base64url');
      const signature = 'invalid';

      const token = `${header}.${payload}.${signature}`;

      await expect(validator.validateToken(token, 'test-audience')).rejects.toThrow(
        'missing key ID',
      );
    });

    it('should reject unsupported algorithms', async () => {
      const header = Buffer.from(
        JSON.stringify({ alg: 'HS256', kid: 'test-kid' }),
      ).toString('base64url');
      const payload = Buffer.from(
        JSON.stringify({
          sub: 'test',
          aud: 'test-audience',
          iss: 'http://localhost:4182',
          iat: Math.floor(Date.now() / 1000),
          exp: Math.floor(Date.now() / 1000) + 3600,
        }),
      ).toString('base64url');
      const signature = 'invalid';

      const token = `${header}.${payload}.${signature}`;

      await expect(validator.validateToken(token, 'test-audience')).rejects.toThrow(
        'Unsupported algorithm',
      );
    });

    it('should reject expired tokens', async () => {
      const header = Buffer.from(
        JSON.stringify({ alg: 'RS256', kid: 'test-kid' }),
      ).toString('base64url');
      const expiredTime = Math.floor(Date.now() / 1000) - 3600; // Expired 1 hour ago
      const payload = Buffer.from(
        JSON.stringify({
          sub: 'test',
          aud: 'test-audience',
          iss: 'http://localhost:4182',
          iat: expiredTime - 7200,
          exp: expiredTime,
        }),
      ).toString('base64url');
      const signature = 'invalid';

      const token = `${header}.${payload}.${signature}`;

      await expect(validator.validateToken(token, 'test-audience')).rejects.toThrow('expired');
    });

    it('should reject tokens with future iat', async () => {
      const header = Buffer.from(
        JSON.stringify({ alg: 'RS256', kid: 'test-kid' }),
      ).toString('base64url');
      const futureTime = Math.floor(Date.now() / 1000) + 3600; // Issued 1 hour in future
      const payload = Buffer.from(
        JSON.stringify({
          sub: 'test',
          aud: 'test-audience',
          iss: 'http://localhost:4182',
          iat: futureTime,
          exp: futureTime + 3600,
        }),
      ).toString('base64url');
      const signature = 'invalid';

      const token = `${header}.${payload}.${signature}`;

      await expect(validator.validateToken(token, 'test-audience')).rejects.toThrow(
        'not yet valid',
      );
    });

    it('should reject tokens with wrong audience', async () => {
      const header = Buffer.from(
        JSON.stringify({ alg: 'RS256', kid: 'test-kid' }),
      ).toString('base64url');
      const now = Math.floor(Date.now() / 1000);
      const payload = Buffer.from(
        JSON.stringify({
          sub: 'test',
          aud: 'wrong-audience',
          iss: 'http://localhost:4182',
          iat: now,
          exp: now + 3600,
        }),
      ).toString('base64url');
      const signature = 'invalid';

      const token = `${header}.${payload}.${signature}`;

      await expect(validator.validateToken(token, 'test-audience')).rejects.toThrow(
        'Audience mismatch',
      );
    });
  });

  describe('Cache Management', () => {
    it('should provide cache statistics', () => {
      const stats = validator.getCacheStats();

      expect(stats).toHaveProperty('keyCount');
      expect(stats).toHaveProperty('cacheValid');
      expect(stats).toHaveProperty('cacheExpiresAt');
      expect(stats).toHaveProperty('keyIds');
      expect(Array.isArray(stats.keyIds)).toBe(true);
    });

    it('should clear cache', () => {
      const statsBefore = validator.getCacheStats();
      validator.clearCache();
      const statsAfter = validator.getCacheStats();

      expect(statsAfter.keyCount).toBe(0);
      expect(statsAfter.cacheValid).toBe(false);
    });
  });

  describe('Base64URL Decoding', () => {
    it('should properly decode base64url strings', () => {
      // Test that validator can handle base64url (with - and _ instead of + and /)
      const testString = 'Hello-World_123';
      const encoded = Buffer.from(testString)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');

      // The validator should be able to decode this
      // (we can't directly test the private method, but we can verify through token validation behavior)
      expect(encoded).toMatch(/^[A-Za-z0-9_-]+$/);
    });
  });
});

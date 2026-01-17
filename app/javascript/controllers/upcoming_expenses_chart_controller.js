import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

export default class extends Controller {
  static values = {
    data: Object,
    currency: String
  };

  connect() {
    this._render();
    this._setupResizeObserver();
  }

  disconnect() {
    this._teardownResizeObserver();
  }

  _setupResizeObserver() {
    this._resizeObserver = new ResizeObserver(() => this._render());
    this._resizeObserver.observe(this.element);
  }

  _teardownResizeObserver() {
    this._resizeObserver?.disconnect();
  }

  _render() {
    const dataObj = this.dataValue || {};
    const data = dataObj.values || [];

    if (!data || !data.length) return;

    // Clear
    this.element.innerHTML = "";

    const margin = { top: 8, right: 8, bottom: 32, left: 8 };

    // Using parent element height or fallback
    const parentHeight = this.element.clientHeight || 208;
    const width = Math.max(320, this.element.clientWidth - margin.left - margin.right);
    const height = Math.max(120, parentHeight - margin.top - margin.bottom);

    const svg = d3.select(this.element)
      .append('svg')
      .attr('width', width + margin.left + margin.right)
      .attr('height', height + margin.top + margin.bottom)
      .attr('role', 'img')
      .attr('aria-label', 'Upcoming monthly expenses')
      .append('g')
      .attr('transform', `translate(${margin.left},${margin.top})`);

    const values = data.map(d => Math.max(0, +d.value || 0));
    const maxValue = d3.max(values) || 1;

    const x = d3.scaleBand().domain(d3.range(data.length)).range([0, width]).padding(0.22);
    const y = d3.scaleLinear().domain([0, maxValue]).nice().range([height, 0]);

    // Bars with red gradient fade
    const bars = svg.selectAll('.bar')
      .data(data)
      .enter()
      .append('rect')
      .attr('class', 'bar')
      .attr('x', (d, i) => x(i))
      .attr('width', x.bandwidth())
      .attr('y', d => {
        const v = Math.max(0, +d.value || 0);
        const yVal = y(v);
        // Ensure small visible bar height for tiny but non-zero values
        if (v > 0 && (height - yVal) < 2) return height - 2;
        return yVal;
      })
      .attr('height', d => {
        const v = Math.max(0, +d.value || 0);
        const barHeight = height - y(v);
        if (v > 0 && barHeight < 2) return 2;
        return barHeight;
      })
      .attr('rx', 6)
      .attr('fill', (d, i) => {
        // Gradient from bright red → darker muted orange → darker muted yellow
        const progress = i / (data.length - 1); // 0 to 1

        if (progress < 0.33) {
          // Bright Red to Darker Orange (0-33%)
          const t = progress / 0.33;
          const r = Math.round(239 - (50 * t)); // 239 → 189
          const g = Math.round(68 + (52 * t)); // 68 → 120
          const b = Math.round(68 - (48 * t)); // 68 → 20
          return `rgb(${r}, ${g}, ${b})`;
        } else if (progress < 0.66) {
          // Darker Orange to Darker Yellow (33-66%)
          const t = (progress - 0.33) / 0.33;
          const r = Math.round(189 - (24 * t)); // 189 → 165
          const g = Math.round(120 + (20 * t)); // 120 → 140
          const b = Math.round(20 - (5 * t)); // 20 → 15
          return `rgb(${r}, ${g}, ${b})`;
        } else {
          // Darker Yellow to Dark Muted Yellow (66-100%)
          const t = (progress - 0.66) / 0.34;
          const r = Math.round(165 - (40 * t)); // 165 → 125
          const g = Math.round(140 - (30 * t)); // 140 → 110
          const b = Math.round(15 - (5 * t)); // 15 → 10
          return `rgb(${r}, ${g}, ${b})`;
        }
      })
      .attr('stroke', (d, i) => i === 0 ? 'white' : 'none')
      .attr('stroke-width', (d, i) => i === 0 ? 2 : 0);

    // Add simple tooltips (accessible)
    bars.append('title').text(d => this._formatCurrency(d.value));

    // Value labels on top of bars (abbreviated)
    svg.selectAll('.bar-value')
      .data(data)
      .enter()
      .append('text')
      .attr('class', 'bar-value')
      .attr('x', (d, i) => x(i) + x.bandwidth() / 2)
      .attr('y', d => {
        const v = Math.max(0, +d.value || 0);
        const yVal = y(v);
        // Position text with bigger gap above bars
        const textY = yVal - 18; // 18px above bar
        return Math.max(6, textY); // Never go above 6px from chart top
      })
      .attr('text-anchor', 'middle')
      .attr('font-size', '11px')
      .attr('font-weight', 600)
      .style('fill', 'currentColor')
      .attr('class', 'text-primary')
      .text(d => d.value ? this._abbreviateNumber(d.value, this.currencyValue) : '—');

    // Month labels
    svg.selectAll('.month-label')
      .data(data)
      .enter()
      .append('text')
      .attr('class', 'month-label text-secondary fill-current')
      .attr('x', (d, i) => x(i) + x.bandwidth() / 2)
      .attr('y', height + 20)
      .attr('text-anchor', 'middle')
      .attr('font-size', '11px')
      .text(d => {
        // Parse date string (YYYY-MM-DD format)
        const dateParts = d.date.split('-');
        const year = dateParts[0].slice(-2); // Get last 2 digits of year
        const month = parseInt(dateParts[1], 10); // Remove leading zero
        return `${month}/${year}`;
      });
  }

  _abbreviateNumber(value, currency) {
    // Simple abbreviation: 1,234 -> $1.2k ; maintain sign and currency symbol
    const v = Math.abs(value);
    if (v >= 1_000_000) return `${this._currencySymbol(currency)}${(value / 1_000_000).toFixed(1)}m`;
    if (v >= 1000) return `${this._currencySymbol(currency)}${(value / 1000).toFixed(1)}k`;
    return `${this._currencySymbol(currency)}${Math.round(value)}`;
  }

  _currencySymbol(currency) {
    try {
      return (0).toLocaleString(undefined, { style: 'currency', currency }).replace(/0|\.|,/g, '').trim();
    } catch (err) {
      return '$';
    }
  }

  _formatCurrency(value) {
    try {
      const currency = this.currencyValue || 'USD';
      return new Intl.NumberFormat(undefined, { style: 'currency', currency, maximumFractionDigits: 0 }).format(value || 0);
    } catch (err) {
      return `$${Math.round(value || 0)}`;
    }
  }
}


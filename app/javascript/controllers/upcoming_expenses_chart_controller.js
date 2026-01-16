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
    const data = this.dataValue || JSON.parse(this.element.dataset.upcomingExpensesChartDataValue || '[]');
    if (!data || !data.length) return;

    // Clear
    this.element.innerHTML = "";

    const margin = { top: 8, right: 8, bottom: 18, left: 8 };

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

    const x = d3.scaleBand().domain(d3.range(data.length)).range([0, width]).padding(0.14);
    const y = d3.scaleLinear().domain([0, maxValue]).nice().range([height, 0]);

    // Bars
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
        if (v > 0 && (height - yVal) < 2) return y(1); // draw minimal bar
        return yVal;
      })
      .attr('height', d => {
        const v = Math.max(0, +d.value || 0);
        const barHeight = height - y(v);
        if (v > 0 && barHeight < 2) return 2;
        return barHeight;
      })
      .attr('rx', 6)
      .attr('fill', (d, i) => i === 0 ? 'var(--color-red-500)' : 'var(--color-gray-200)')
      .attr('opacity', (d, i) => i === 0 ? 1 : Math.max(0.25, 1 - (i / (data.length * 1.05))));

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
        const yVal = y(v) - 8;
        // keep labels readable and inside chart
        return Math.max(12, yVal);
      })
      .attr('text-anchor', 'middle')
      .attr('font-size', '12px')
      .attr('font-weight', 600)
      .attr('fill', (d, i) => i === 0 ? 'var(--color-white)' : 'var(--color-primary)')
      .text(d => d.value ? this._abbreviateNumber(d.value, this.currencyValue) : '—');

    // X-axis legend below as labels were added server-side, we keep layout minimal here
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


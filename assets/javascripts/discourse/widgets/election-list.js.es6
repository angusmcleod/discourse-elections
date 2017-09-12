import { createWidget } from 'discourse/widgets/widget';
import { ajax } from 'discourse/lib/ajax';
import { h } from 'virtual-dom';

export default createWidget('election-list', {
  tagName: 'div.election-list',
  buildKey: () => 'election-list',

  defaultState() {
    return {
      elections: [],
      loading: true
    };
  },

  getElections() {
    const category = this.attrs.category;

    if (!category) {
      this.state.loading = false;
      this.scheduleRerender();
      return;
    }

    ajax(`/election/category-list`, { data: { category_id: category.id }}).then((elections) => {
      this.state.elections = elections;
      this.state.loading = false;
      this.scheduleRerender();
    });
  },


  html(attrs, state) {
    const elections = state.elections;
    const loading = state.loading;
    let contents = [];

    if (loading) {
      this.getElections();
    } else if (elections.length > 0) {
      contents.push(h('span', `${I18n.t('election.list.label')}: `));
      contents.push(h('ul', elections.map((e, i) => {
        let item = [];

        if (i > 0) {
          item.push(h('span', ', '));
        }

        item.push(h('a', { href: e.relative_url }, h('span', e.position)));

        return h('li', item);
      })));
    }

    return contents;
  }
});

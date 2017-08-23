import { createWidget } from 'discourse/widgets/widget';
import showModal from 'discourse/lib/show-modal';

export default createWidget('election-list-controls', {
  tagName: 'div.election-list-controls',

  html(attrs) {
    const category = attrs.category;
    const user = this.currentUser;
    let links = [];

    if (user && user.is_elections_admin) {
      links.push(this.attach('link', {
        icon: 'plus',
        label: 'election.create.label',
        action: 'createElection',
      }));
    }

    return links;
  },

  createElection() {
    showModal('create-election', {
      model: {
        categoryId: this.attrs.category.id
      }
    });
  }
})

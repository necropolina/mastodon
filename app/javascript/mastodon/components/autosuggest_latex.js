import React from 'react';
import PropTypes from 'prop-types';

const assetHost = process.env.CDN_HOST || '';

export default class AutosuggestLatex extends React.PureComponent {

  static propTypes = {
    latex: PropTypes.object.isRequired,
  };

  setRef = (c) => {
    this.node = c;
  }

  componentDidMount() {
    try {
      MathJax.typeset([this.node]);
    } catch(e) {
      console.error(e);
    }

  }

  render () {
    const { latex } = this.props;

    return (
      <div className='autosuggest-latex' ref={this.setRef}>
        \({latex.expression}\)
      </div>
    );
  }

}
